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
			{type: "response.unknown"},
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
	
	with "#models" do
		it "exposes the configured Codex client version" do
			previous_version = ENV["CODEX_CLIENT_VERSION"]
			ENV["CODEX_CLIENT_VERSION"] = "0.158.0"
			
			expect(subject.client_version).to be == "0.158.0"
		ensure
			if previous_version
				ENV["CODEX_CLIENT_VERSION"] = previous_version
			else
				ENV.delete("CODEX_CLIENT_VERSION")
			end
		end
		
		it "fetches visible API-supported models and normalizes their metadata" do
			catalog = {
				models: [
					{slug: "gpt-visible", display_name: "GPT Visible", supported_in_api: true, visibility: "list", context_window: 272_000},
					{slug: "gpt-hidden", display_name: "GPT Hidden", supported_in_api: true, visibility: "hide"},
					{slug: "gpt-unsupported", display_name: "GPT Unsupported", supported_in_api: false, visibility: "list"},
					{slug: "", supported_in_api: true, visibility: "list"},
				],
			}
			upstream = Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [JSON.dump(catalog)]]
			client = Class.new do
				attr :requests
				
				def initialize(response)
					@response = response
					@requests = []
				end
				
				def call(request)
					@requests << request
					@response
				end
			end.new(upstream)
			authentication = Class.new do
				def credentials(refresh: false)
					{access_token: "test-token", account_id: "test-account", residency: "eu"}
				end
			end.new
			provider = subject.new(authentication: authentication, client_version: "0.157.0", client: client)
			
			response = provider.models
			models = JSON.parse(response.read).fetch("data")
			request = client.requests.first
			
			expect(response.status).to be == 200
			expect(request.method).to be == "GET"
			expect(request.path).to be == "/backend-api/codex/models?client_version=0.157.0"
			expect(request.headers["authorization"]).to be == "Bearer test-token"
			expect(Array(request.headers["chatgpt-account-id"]).first).to be == "test-account"
			expect(Array(request.headers["originator"]).first).to be == "laiya"
			expect(Array(request.headers["x-openai-internal-codex-residency"]).first).to be == "eu"
			expect(models).to be == [{
				"id" => "gpt-visible",
				"object" => "model",
				"created" => 0,
				"owned_by" => "codex",
				"laiya" => {"name" => "GPT Visible", "limits" => {"context" => 272_000}},
			}]
		ensure
			response&.close
			provider&.close
		end
		
		it "preserves upstream model catalog errors" do
			upstream = Protocol::HTTP::Response[503, {"content-type" => "application/json"}, ['{"error":"unavailable"}']]
			client = Class.new do
				def initialize(response)
					@response = response
				end
				
				def call(_request)
					@response
				end
			end.new(upstream)
			provider = subject.new(authentication: auth, client_version: "0.157.0", client: client)
			
			response = provider.models
			
			expect(response.status).to be == 503
			expect(response.read).to be == '{"error":"unavailable"}'
		ensure
			response&.close
			provider&.close
		end
		
		it "maps authentication and unexpected model discovery failures to server errors" do
			failing_authentication = Class.new do
				def credentials(refresh: false)
					raise Laiya::Provider::Codex::Authentication::Error
				end
			end.new
			provider = subject.new(authentication: failing_authentication, client_version: "0.157.0", client: client)
			response = provider.models
			
			expect(response.status).to be == 502
			expect(JSON.parse(response.read).dig("error", "message")).to be == "Codex authentication failed"
			response.close
			
			unexpected_authentication = Class.new do
				def credentials(refresh: false)
					raise IOError, "Connection failed"
				end
			end.new
			provider = subject.new(authentication: unexpected_authentication, client_version: "0.157.0", client: client)
			response = provider.models
			
			expect(response.status).to be == 502
			expect(JSON.parse(response.read).dig("error", "message")).to be == "Codex model discovery failed"
		ensure
			response&.close
			provider&.close
		end
		
		it "refreshes credentials and retries an unauthorized model request" do
			authentication = Class.new do
				attr :refresh_requests
				
				def initialize
					@refresh_requests = []
				end
				
				def credentials(refresh: false)
					@refresh_requests << refresh
					{access_token: refresh ? "new-token" : "old-token"}
				end
			end.new
			responses = [
				Protocol::HTTP::Response[401],
				Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [JSON.dump(models: [])]],
			]
			client = Class.new do
				attr :requests
				
				def initialize(responses)
					@responses = responses
					@requests = []
				end
				
				def call(request)
					@requests << request
					@responses.shift
				end
			end.new(responses)
			provider = subject.new(authentication: authentication, client_version: "0.157.0", client: client)
			
			response = provider.models
			
			expect(response.status).to be == 200
			expect(authentication.refresh_requests).to be == [false, true]
			expect(client.requests.length).to be == 2
			expect(client.requests.last.headers["authorization"]).to be == "Bearer new-token"
		ensure
			response&.close
			provider&.close
		end
		
		it "detects the installed Codex CLI version when no override is configured" do
			status = Class.new do
				def success?
					true
				end
			end.new
			catalog_client = Class.new do
				attr :requests
				
				def initialize
					@requests = []
				end
				
				def call(request)
					@requests << request
					Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [JSON.dump(models: [])]]
				end
			end.new
			provider = subject.new(authentication: auth, client_version: nil, client: catalog_client)
			response = nil
			
			mock(Open3) do |wrapper|
				wrapper.replace(:capture2) do |*arguments|
					expect(arguments).to be == ["codex", "--version"]
					["codex-cli 0.157.0\n", status]
				end
				
				response = provider.models
			end
			
			expect(response.status).to be == 200
			expect(catalog_client.requests.first.path).to be == "/backend-api/codex/models?client_version=0.157.0"
		ensure
			response&.close
			provider&.close
		end
		
		it "requires a client version and rejects malformed catalogs" do
			provider = subject.new(authentication: auth, client_version: nil, client: client)
			response = nil
			mock(Open3) do |wrapper|
				wrapper.replace(:capture2) do |*arguments|
					raise Errno::ENOENT
				end
				
				response = provider.models
				
				expect(response.status).to be == 500
				expect(JSON.parse(response.read).dig("error", "message")).to be(:include?, "CODEX_CLIENT_VERSION")
				expect(client.requests).to be(:empty?)
			end
			response.close
			
			invalid_client = Class.new do
				def call(_request)
					Protocol::HTTP::Response[200, {"content-type" => "application/json"}, ['{"models":{}}']]
				end
			end.new
			provider = subject.new(authentication: auth, client_version: "0.157.0", client: invalid_client)
			response = provider.models
			
			expect(response.status).to be == 502
			response.close
			
			malformed_client = Class.new do
				def call(_request)
					Protocol::HTTP::Response[200, {"content-type" => "application/json"}, ["not json"]]
				end
			end.new
			provider = subject.new(authentication: auth, client_version: "0.157.0", client: malformed_client)
			response = provider.models
			
			expect(response.status).to be == 502
		ensure
			response&.close
			provider&.close
		end
	end
	
	with "#call" do
		it "rejects unsupported methods and endpoints without contacting Codex" do
			request = Protocol::HTTP::Request["GET", "/v1/models"]
			response = provider.call(request)
			
			expect(response.status).to be == 404
			expect(client.requests).to be(:empty?)
		ensure
			response&.close
		end
		
		it "rejects a non-object JSON payload" do
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/responses",
				{"content-type" => "application/json"},
				[JSON.dump(["not", "an", "object"])],
			]
			response = provider.call(request)
			
			expect(response.status).to be == 400
			expect(JSON.parse(response.read).dig("error", "type")).to be == "invalid_request_error"
		ensure
			response&.close
		end
		
		it "rejects Chat Completions requests that request multiple choices" do
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", n: 2, messages: [])],
			]
			response = provider.call(request)
			
			expect(response.status).to be == 400
			expect(client.requests).to be(:empty?)
		ensure
			response&.close
		end
		
		it "refreshes credentials and retries an unauthorized upstream request" do
			authentication = Class.new do
				attr :refresh_requests
				
				def initialize
					@refresh_requests = []
				end
				
				def credentials(refresh: false)
					@refresh_requests << refresh
					{access_token: refresh ? "new-token" : "old-token"}
				end
			end.new
			responses = [Protocol::HTTP::Response[401], upstream_response]
			client = Class.new do
				attr :requests
				
				def initialize(responses)
					@responses = responses
					@requests = []
				end
				
				def call(request)
					@requests << request
					@responses.shift
				end
			end.new(responses)
			provider = subject.new(authentication: authentication, client: client)
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", messages: [{role: "user", content: "Hello"}])],
			]
			
			response = provider.call(request)
			
			expect(response.status).to be == 200
			expect(authentication.refresh_requests).to be == [false, true]
			expect(client.requests.length).to be == 2
		ensure
			response&.close
			provider&.close
		end
		
		it "maps authentication and unexpected failures to server errors" do
			failing_authentication = Class.new do
				def credentials(refresh: false)
					raise Laiya::Provider::Codex::Authentication::Error
				end
			end.new
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", messages: [])],
			]
			response = subject.new(authentication: failing_authentication, client: client).call(request)
			
			expect(response.status).to be == 502
			response.close
			
			failing_client = Class.new do
				def call(_request)
					raise IOError, "connection failed"
				end
			end.new
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", messages: [])],
			]
			response = subject.new(authentication: auth, client: failing_client).call(request)
			
			expect(response.status).to be == 502
		ensure
			response&.close
		end
		
		it "forwards credential residency metadata" do
			residency_authentication = Class.new do
				def credentials(refresh: false)
					{access_token: "test-token", account_id: "test-account", residency: "eu"}
				end
			end.new
			provider = subject.new(authentication: residency_authentication, client: client)
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", messages: [])],
			]
			
			response = provider.call(request)
			expect(Array(client.requests.first[:request].headers["x-openai-internal-codex-residency"]).first).to be == "eu"
		ensure
			response&.close
			provider&.close
		end
		
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
		
		it "streams function calls and optional usage for the client" do
			events = [
				{type: "response.created", response: {id: "resp_tools", model: "gpt-test"}},
				{type: "response.output_item.added", output_index: 0, item: {id: "item_1", call_id: "call_1", type: "function_call", name: "weather"}},
				{type: "response.function_call_arguments.delta", output_index: 0, item_id: "item_1", delta: "{\"city\":\"Paris\"}"},
				{type: "response.completed", response: {id: "resp_tools", model: "gpt-test", output: [{type: "function_call", call_id: "call_1"}], usage: {input_tokens: 5, output_tokens: 2}}},
			]
			body = events.map{|event| "data: #{JSON.dump(event)}\n\n"}.join
			upstream = Protocol::HTTP::Response[200, {"content-type" => "text/event-stream"}, [body]]
			client_with_tool_response = Class.new do
				def initialize(response)
					@response = response
				end
				
				def call(_request)
					@response
				end
			end.new(upstream)
			provider = subject.new(authentication: auth, client: client_with_tool_response)
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", stream: true, stream_options: {include_usage: true}, messages: [{role: "user", content: "Check the weather."}])],
			]
			
			response = provider.call(request)
			chunks = response.read.lines.grep(/^data: /).map{|line| line.delete_prefix("data: ").strip}.reject{|line| line == "[DONE]"}.map{|line| JSON.parse(line)}
			tool_chunk = chunks.find{|chunk| chunk.dig("choices", 0, "delta", "tool_calls")}
			usage_chunk = chunks.find{|chunk| chunk["usage"]}
			
			expect(tool_chunk.dig("choices", 0, "delta", "tool_calls", 0, "function", "name")).to be == "weather"
			expect(tool_chunk.dig("choices", 0, "delta", "tool_calls", 0, "function", "arguments")).to be == ""
			expect(usage_chunk.dig("usage", "total_tokens")).to be == 7
		ensure
			response&.close
			provider&.close
		end
		
		it "streams refusal events and incomplete-response errors" do
			refusal_events = [
				{type: "response.created", response: {id: "resp_refusal", model: "gpt-test"}},
				{type: "response.refusal.delta", delta: "I cannot help with that."},
				{type: "response.completed", response: {id: "resp_refusal", model: "gpt-test", output: []}},
			]
			refusal_body = refusal_events.map{|event| "data: #{JSON.dump(event)}\n\n"}.join
			upstream = Protocol::HTTP::Response[200, {"content-type" => "text/event-stream"}, [refusal_body]]
			refusal_client = Class.new do
				def initialize(response)
					@response = response
				end
				
				def call(_request)
					@response
				end
			end.new(upstream)
			provider = subject.new(authentication: auth, client: refusal_client)
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", stream: true, messages: [])],
			]
			response = provider.call(request)
			chunks = response.read.lines.grep(/^data: /).map{|line| line.delete_prefix("data: ").strip}.reject{|line| line == "[DONE]"}.map{|line| JSON.parse(line)}
			refusal = chunks.find{|chunk| chunk.dig("choices", 0, "delta", "refusal")}
			expect(refusal.dig("choices", 0, "delta", "refusal")).to be == "I cannot help with that."
			response.close
			provider.close
			
			failed_events = [{type: "response.failed", response: {error: {message: "Codex failed"}}}]
			failed_body = failed_events.map{|event| "data: #{JSON.dump(event)}\n\n"}.join
			failed_response = Protocol::HTTP::Response[200, {"content-type" => "text/event-stream"}, [failed_body]]
			failed_client = Class.new do
				def initialize(response)
					@response = response
				end
				
				def call(_request)
					@response
				end
			end.new(failed_response)
			provider = subject.new(authentication: auth, client: failed_client)
			failed_request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[JSON.dump(model: "gpt-test", stream: true, messages: [])],
			]
			response = provider.call(failed_request)
			body = response.read
			
			expect(body).to be(:include?, "Codex failed")
			expect(body).to be(:include?, "Codex ended without a completed response")
		ensure
			response&.close
			provider&.close
		end
		
		it "returns errors for failed and incomplete non-streaming Responses" do
			[
				[{type: "error", error: {message: "Codex failed"}}],
				[{type: "response.created", response: {id: "resp_open"}}],
			].each do |events|
				body = events.map{|event| "data: #{JSON.dump(event)}\n\n"}.join
				upstream = Protocol::HTTP::Response[200, {"content-type" => "text/event-stream"}, [body]]
				client = Class.new do
					def initialize(response)
						@response = response
					end
					
					def call(_request)
						@response
					end
				end.new(upstream)
				provider = subject.new(authentication: auth, client: client)
				request = Protocol::HTTP::Request[
					"POST",
					"/v1/responses",
					{"content-type" => "application/json"},
					[JSON.dump(model: "gpt-test", input: "Hello")],
				]
				response = provider.call(request)
				
				expect(response.status).to be == 502
				response.close
				provider.close
			end
		end
		
		it "returns errors for failed and incomplete Chat Completions" do
			[
				[{type: "response.failed", response: {error: {message: "Codex failed"}}}],
				[{type: "response.created", response: {id: "resp_open"}}],
			].each do |events|
				body = events.map{|event| "data: #{JSON.dump(event)}\n\n"}.join
				upstream = Protocol::HTTP::Response[200, {"content-type" => "text/event-stream"}, [body]]
				client = Class.new do
					def initialize(response)
						@response = response
					end
					
					def call(_request)
						@response
					end
				end.new(upstream)
				provider = subject.new(authentication: auth, client: client)
				request = Protocol::HTTP::Request[
					"POST",
					"/v1/chat/completions",
					{"content-type" => "application/json"},
					[JSON.dump(model: "gpt-test", messages: [])],
				]
				response = provider.call(request)
				
				expect(response.status).to be == 502
				response.close
				provider.close
			end
		end
		
		it "closes an authentication source that supports closing" do
			authentication = Class.new do
				attr :closed
				
				def close
					@closed = true
				end
			end.new
			provider = subject.new(authentication: authentication, client: client)
			
			provider.close
			
			expect(authentication.closed).to be == true
		end
	end
end
