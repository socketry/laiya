# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya/provider/codex"
require "sus/fixtures/async/reactor_context"

describe Laiya::Provider::Codex do
	include Sus::Fixtures::Async::ReactorContext
	
	let(:auth) do
		Class.new do
			def credentials(refresh: false)
				{access_token: "test-token", account_id: "test-account"}
			end
		end.new
	end
	let(:upstream_response) do
		events = [
			{type: "response.created", response: {id: "resp_123", model: "gpt-test"}},
			{
				type: "response.output_item.added",
				output_index: 0,
				item: {id: "msg_123", type: "message", role: "assistant", content: []},
			},
			{type: "response.output_text.delta", delta: "Hello"},
			{
				type: "response.completed",
				response: {
					id: "resp_123",
					model: "gpt-test",
					output: [],
					usage: {input_tokens: 4, output_tokens: 1, total_tokens: 5},
				},
			},
		]
		body = events.map{|event| "data: #{JSON.dump(event)}\n\n"}.join
		
		Protocol::HTTP::Response[200, {"content-type" => "text/event-stream"}, [
			body,
		]]
	end
	let(:client) do
		Class.new do
			attr :requests
			
			def initialize(response)
				@response = response
				@requests = []
			end
			
			def call(request)
				@requests << {request: request, body: request.read}
				@response
			end
		end.new(upstream_response)
	end
	let(:provider) {subject.new(authentication: auth, client: client)}
	
	with "#call" do
		with "an upstream error response" do
			let(:upstream_response) do
				Protocol::HTTP::Response[
					400,
					{"content-type" => "application/json"},
					['{"error":{"message":"invalid Responses input","type":"invalid_request_error","code":"invalid_input"}}'],
				]
			end
			
			it "preserves the Codex error response for client diagnostics" do
				request = Protocol::HTTP::Request[
					"POST",
					"/v1/responses",
					{"content-type" => "application/json"},
					[JSON.dump(model: "gpt-test", input: "Hello", stream: true)],
				]
				
				response = provider.call(request)
				
				expect(response.status).to be == 400
				expect(JSON.parse(response.read).dig("error", "code")).to be == "invalid_input"
			ensure
				response&.close
			end
		end
		
		it "preserves native Responses tool history and streaming for the client" do
			body = JSON.dump(
				model: "gpt-test",
				stream: true,
				input: [
					{type: "function_call", call_id: "call_1", name: "weather", arguments: "{}"},
					{type: "function_call_output", call_id: "call_1", output: "Sunny"},
					{type: "reasoning", encrypted_content: "opaque-reasoning"},
				],
				tools: [{type: "function", name: "weather", parameters: {type: "object"}}],
			)
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/responses",
				{"content-type" => "application/json", "session-id" => "opencode-session"},
				[body],
			]
			
			response = provider.call(request)
			forwarded = client.requests.first
			codex_request = JSON.parse(forwarded[:body])
			
			expect(response).to be_equal(upstream_response)
			expect(codex_request["input"][1]["type"]).to be == "function_call_output"
			expect(codex_request["input"][2]["encrypted_content"]).to be == "opaque-reasoning"
			expect(codex_request["tools"][0]["name"]).to be == "weather"
			expect(codex_request["store"]).to be == false
			expect(codex_request["include"]).to be(:include?, "reasoning.encrypted_content")
			expect(Array(forwarded[:request].headers["session-id"]).first).to be == "opencode-session"
		ensure
			response&.close
		end
		
		it "returns a completed Responses object for non-streaming client requests" do
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/responses",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", input: [{role: "user", content: "Hello"}])],
			]
			
			response = provider.call(request)
			result = JSON.parse(response.read)
			
			expect(response.status).to be == 200
			expect(result["id"]).to be == "resp_123"
			expect(result["output"].first.dig("content", 0, "text")).to be == "Hello"
		ensure
			response&.close
		end
		
		it "rejects stored previous-response references in stateless Codex mode" do
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/responses",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", previous_response_id: "resp_previous", input: "Continue")],
			]
			
			response = provider.call(request)
			
			expect(response.status).to be == 400
			expect(JSON.parse(response.read).dig("error", "type")).to be == "invalid_request_error"
			expect(client.requests).to be(:empty?)
		ensure
			response&.close
		end
		
		it "directs Chat Completions tool turns to the native Responses API" do
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", messages: [], tools: [{type: "function", function: {name: "weather"}}])],
			]
			
			response = provider.call(request)
			
			expect(response.status).to be == 400
			expect(JSON.parse(response.read).dig("error", "type")).to be == "invalid_request_error"
			expect(client.requests).to be(:empty?)
		ensure
			response&.close
		end
		
		it "converts a Chat Completions request to Codex Responses and maps the response back" do
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", messages: [{role: "user", content: "Hello"}])],
			]
			
			response = provider.call(request)
			result = JSON.parse(response.read)
			forwarded = client.requests.first
			codex_request = JSON.parse(forwarded[:body])
			
			expect(response.status).to be == 200
			expect(result.dig("choices", 0, "message", "content")).to be == "Hello"
			expect(result.dig("usage", "total_tokens")).to be == 5
			expect(codex_request["stream"]).to be == true
			expect(codex_request["store"]).to be == false
			expect(codex_request.dig("input", 0, "content")).to be == "Hello"
			expect(forwarded[:request].path).to be == "/backend-api/codex/responses"
			expect(forwarded[:request].headers["authorization"]).to be == "Bearer test-token"
			expect(Array(forwarded[:request].headers["chatgpt-account-id"]).first).to be == "test-account"
		ensure
			response&.close
		end
		
		it "streams Chat Completions chunks, including end-of-stream" do
			body = JSON.dump(model: "gpt-test", stream: true, messages: [{role: "user", content: "Hello"}])
			request = Protocol::HTTP::Request["POST", "/v1/chat/completions", {"content-type" => "application/json"}, [body]]
			
			response = provider.call(request)
			chunks = response.read.lines.grep(/^data: /).map{|line| line.delete_prefix("data: ").strip}
			
			expect(response.headers["content-type"]).to be == "text/event-stream"
			expect(chunks.last).to be == "[DONE]"
			expect(chunks.any?{|chunk| JSON.parse(chunk).dig("choices", 0, "delta", "content") == "Hello"}).to be_truthy
		ensure
			response&.close
		end
	end
end
