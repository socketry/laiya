# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http"
require "json"
require "open3"
require "protocol/http/body/streamable"
require "securerandom"
require "uri"

require_relative "interface"
require_relative "codex/authentication"
require_relative "codex/request"
require_relative "codex/response"
require_relative "codex/responses"
require_relative "codex/server_sent_events"

module Laiya
	module Provider
		# Adapts OpenAI Chat Completions HTTP to the ChatGPT Codex Responses backend.
		#
		# This experimental integration uses the Codex-specific backend, not the public
		# OpenAI Platform API. Responses API tool calls are returned to the HTTP client;
		# this provider never executes them.
		class Codex < Interface
			DEFAULT_ENDPOINT = "https://chatgpt.com/backend-api/codex"
			USER_AGENT = "laiya-codex/0.0.0"
			
			# Return the configured or installed Codex CLI version.
			# @returns [String | Nil] The Codex CLI version, or `nil` when it cannot be detected.
			def self.client_version
				if version = ENV["CODEX_CLIENT_VERSION"]
					return version unless version.empty?
				end
				
				output, status = Open3.capture2("codex", "--version")
				return unless status.success?
				
				return output[/\bcodex(?:-cli)?\s+(\S+)/, 1]
			rescue Errno::ENOENT
				nil
			end
			
			# Initialize the experimental ChatGPT Codex API adapter.
			# @option :authentication [Interface(:credentials) | Nil] A credential source.
			# @option :codex_home [String] The Codex home directory containing `auth.json`.
			# @option :client_version [String | Nil] The Codex CLI version used for model discovery; defaults to `CODEX_CLIENT_VERSION` or `codex --version`.
			# @option :endpoint [String | Async::HTTP::Endpoint] The Codex backend endpoint.
			# @option :client [Interface(:call) | Nil] An optional HTTP client.
			def initialize(authentication: nil, codex_home: ENV.fetch("CODEX_HOME", Authentication::DEFAULT_CODEX_HOME), client_version: ENV["CODEX_CLIENT_VERSION"], endpoint: DEFAULT_ENDPOINT, client: nil, **client_options)
				@endpoint = Async::HTTP::Endpoint[endpoint]
				@authentication = authentication || Authentication.new(codex_home: codex_home)
				@client_version = client_version
				@client_version_detected = client_version && !client_version.empty?
				@client = client || Async::HTTP::Client.new(@endpoint, **client_options)
				@owns_client = client.nil?
			end
			
			attr :endpoint
			
			# Fetch and normalize the authenticated Codex model catalog.
			# @returns [Protocol::HTTP::Response] The OpenAI-compatible model list.
			def models
				client_version = self.client_version
				unless client_version
					return error_response(500, "Set CODEX_CLIENT_VERSION or install the Codex CLI to discover models", "server_error")
				end
				
				credentials = @authentication.credentials
				upstream = request_models(credentials, client_version)
				
				if upstream.status == 401
					upstream.close
					credentials = @authentication.credentials(refresh: true)
					upstream = request_models(credentials, client_version)
				end
				
				unless upstream.status >= 200 && upstream.status < 300
					return upstream
				end
				
				model_catalog_response(upstream)
			rescue Authentication::Error
				error_response(502, "Codex authentication failed", "server_error")
			rescue StandardError
				error_response(502, "Codex model discovery failed", "server_error")
			end
			
			# Convert supported Chat Completions requests or proxy Responses requests.
			# @parameter request [Protocol::HTTP::Request] The incoming OpenAI-compatible request.
			# @returns [Protocol::HTTP::Response] The translated or proxied response.
			def call(request)
				path = request.path.split("?", 2).first
				unless request.method == "POST" && %w[/v1/chat/completions /v1/responses].include?(path)
					return error_response(404, "Only /v1/chat/completions and /v1/responses are supported", "not_found_error")
				end
				
				payload = JSON.parse(request.read)
				return error_response(400, "Expected a JSON object", "invalid_request_error") unless payload.is_a?(Hash)
				
				responses_api = path == "/v1/responses"
				if responses_api
					transformed = Responses.prepare(payload)
				else
					if payload["n"] && payload["n"] != 1
						return error_response(400, "Codex Chat Completions supports n=1 only", "invalid_request_error")
					end
					
					if chat_tools?(payload)
						return error_response(400, "Codex tool turns require the /v1/responses endpoint", "invalid_request_error")
					end
					
					transformed = Request.transform(payload)
				end
				
				credentials = @authentication.credentials
				upstream = request_codex(transformed, request, credentials)
				
				if upstream.status == 401
					upstream.close
					credentials = @authentication.credentials(refresh: true)
					upstream = request_codex(transformed, request, credentials)
				end
				
				unless upstream.status >= 200 && upstream.status < 300
					return upstream
				end
				
				if responses_api && payload["stream"]
					return upstream
				elsif responses_api
					return responses_response(upstream)
				end
				
				if payload["stream"]
					return streaming_response(upstream, request, payload, transformed[:model])
				end
				
				return completion_response(upstream, transformed[:model])
			rescue JSON::ParserError, KeyError, ArgumentError, TypeError => error
				error_response(400, error.message, "invalid_request_error")
			rescue Authentication::Error
				error_response(502, "Codex authentication failed", "server_error")
			rescue StandardError
				error_response(502, "Codex provider request failed", "server_error")
			end
			
			# Close the HTTP client and authentication source when owned.
			def close
				@client.close if @owns_client
				@authentication.close if @authentication.respond_to?(:close)
			end
			
			private
			
			def client_version
				return @client_version if @client_version_detected
				
				@client_version_detected = true
				@client_version = self.class.client_version
			end
			
			def request_models(credentials, client_version)
				path = "#{@endpoint.path.split("?", 2).first.sub(/\/+\z/, "")}/models?#{URI.encode_www_form(client_version: client_version)}"
				
				headers = Protocol::HTTP::Headers[
					"accept" => "application/json",
					"authorization" => "Bearer #{credentials.fetch(:access_token)}",
					"originator" => "laiya",
					"user-agent" => USER_AGENT,
				]
				
				if account_id = credentials[:account_id]
					headers["chatgpt-account-id"] = account_id
				end
				
				if residency = credentials[:residency]
					headers["x-openai-internal-codex-residency"] = residency
				end
				
				return @client.call(Protocol::HTTP::Request["GET", path, headers])
			end
			
			def model_catalog_response(upstream)
				payload = JSON.parse(upstream.read)
				models = payload.fetch("models")
				unless models.is_a?(Array)
					return error_response(502, "Codex model catalog was invalid", "server_error")
				end
				
				data = models.filter_map{|model| normalize_model(model)}
				return Protocol::HTTP::Response[
					200,
					{"content-type" => "application/json"},
					[JSON.dump(object: "list", data: data)],
				]
			rescue JSON::ParserError, KeyError, TypeError
				error_response(502, "Codex model catalog was invalid", "server_error")
			ensure
				upstream.close
			end
			
			def normalize_model(model)
				return unless model.is_a?(Hash)
				return unless model["supported_in_api"] == true && model["visibility"] == "list"
				
				id = model["slug"]
				return unless id.is_a?(String) && !id.empty?
				
				metadata = {}
				metadata["name"] = model["display_name"] if model["display_name"].is_a?(String)
				if (context = model["context_window"]).is_a?(Integer) && context.positive?
					metadata["limits"] = {"context" => context}
				end
				efforts = Array(model["supported_reasoning_levels"]).filter_map do |level|
					level["effort"] if level.is_a?(Hash) && level["effort"].is_a?(String) && !level["effort"].empty?
				end.uniq
				if efforts.any?
					reasoning = {"supported_efforts" => efforts}
					if efforts.include?(default_effort = model["default_reasoning_level"])
						reasoning["default_effort"] = default_effort
					end
					metadata["reasoning"] = reasoning
				end
				
				{
					"id" => id,
					"object" => "model",
					"created" => 0,
					"owned_by" => "codex",
					"laiya" => metadata,
				}
			end
			
			def request_codex(payload, request, credentials)
				headers = Protocol::HTTP::Headers[
					"accept" => "text/event-stream",
					"content-type" => "application/json",
					"authorization" => "Bearer #{credentials.fetch(:access_token)}",
					"openai-beta" => "responses=experimental",
					"originator" => "laiya",
					"user-agent" => USER_AGENT,
					"session-id" => session_id(request),
				]
				
				if account_id = credentials[:account_id]
					headers["chatgpt-account-id"] = account_id
				end
				
				if residency = credentials[:residency]
					headers["x-openai-internal-codex-residency"] = residency
				end
				
				codex_request = Protocol::HTTP::Request[
					"POST",
					"#{@endpoint.path.split("?", 2).first.sub(/\/+\z/, "")}/responses",
					headers,
					[JSON.dump(payload)],
				]
				
				return @client.call(codex_request)
			end
			
			def completion_response(upstream, model)
				completed = nil
				collector = Responses::Collector.new
				ServerSentEvents.each(upstream.body) do |event|
					collector.accept(event)
					case event["type"]
					when "response.completed", "response.done"
						completed = collector.complete(event["response"] || event)
					when "response.failed", "error"
						message = event.dig("response", "error", "message") || event.dig("error", "message") || "Codex response failed"
						return error_response(502, message, "server_error")
					end
				end
				
				unless completed
					return error_response(502, "Codex ended without a completed response", "server_error")
				end
				
				body = JSON.dump(Response.completed(completed, requested_model: model))
				return Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [body]]
			ensure
				upstream.close
			end
			
			def responses_response(upstream)
				completed = nil
				collector = Responses::Collector.new
				ServerSentEvents.each(upstream.body) do |event|
					collector.accept(event)
					case event["type"]
					when "response.completed", "response.done"
						completed = collector.complete(event["response"] || event)
					when "response.failed", "error"
						message = event.dig("response", "error", "message") || event.dig("error", "message") || "Codex response failed"
						return error_response(502, message, "server_error")
					end
				end
				
				unless completed
					return error_response(502, "Codex ended without a completed response", "server_error")
				end
				
				return Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [JSON.dump(completed)]]
			ensure
				upstream.close
			end
			
			def streaming_response(upstream, request, payload, model)
				body = Protocol::HTTP::Body::Streamable.response(request) do |stream|
					stream_codex_response(upstream, stream, payload, model)
				end
				
				return Protocol::HTTP::Response[
					200,
					{"content-type" => "text/event-stream", "cache-control" => "no-cache"},
					body,
				]
			end
			
			def stream_codex_response(upstream, stream, payload, model)
				state = {
					id: nil,
					model: model,
					created: Time.now.to_i,
					tools: {},
					has_tools: false,
					role_sent: false,
					completed: false,
				}
				
				ServerSentEvents.each(upstream.body) do |event|
					stream_chunks(event, state, payload).each do |chunk|
						stream.write("data: #{JSON.dump(chunk)}\n\n")
					end
				end
				
				unless state[:completed]
					stream.write("data: #{JSON.dump(error: {message: "Codex ended without a completed response", type: "server_error"})}\n\n")
				end
				
				stream.write("data: [DONE]\n\n")
			ensure
				upstream.close
				stream.close
			end
			
			def stream_chunks(event, state, payload)
				case event["type"]
				when "response.created", "response.in_progress"
					response = event["response"] || {}
					state[:id] = response["id"] || state[:id]
					state[:model] = response["model"] || state[:model]
					state[:created] = response["created_at"] || state[:created]
					return [] if state[:role_sent]
					state[:role_sent] = true
					return [Response.stream_chunk(**stream_metadata(state), delta: {role: "assistant"})]
				when "response.output_text.delta"
					return [Response.stream_chunk(**stream_metadata(state), delta: {content: event["delta"]})]
				when "response.refusal.delta"
					return [Response.stream_chunk(**stream_metadata(state), delta: {refusal: event["delta"]})]
				when "response.output_item.added"
					item = event["item"] || {}
					return [] unless item["type"] == "function_call"
					
					index = event["output_index"] || state[:tools].length
					state[:tools][item["id"] || item["call_id"]] = index
					state[:has_tools] = true
					tool_call = {index: index, id: item["call_id"] || item["id"], type: "function", function: {name: item["name"], arguments: ""}}
					return [Response.stream_chunk(**stream_metadata(state), delta: {tool_calls: [tool_call]})]
				when "response.function_call_arguments.delta"
					index = state[:tools][event["item_id"]] || event["output_index"] || 0
					tool_call = {index: index, function: {arguments: event["delta"]}}
					return [Response.stream_chunk(**stream_metadata(state), delta: {tool_calls: [tool_call]})]
				when "response.completed", "response.done"
					response = event["response"] || event
					state[:id] = response["id"] || state[:id]
					state[:model] = response["model"] || state[:model]
					state[:created] = response["created_at"] || state[:created]
					state[:has_tools] ||= Array(response["output"]).any?{|item| item["type"] == "function_call"}
					state[:completed] = true
					finish_reason = state[:has_tools] ? "tool_calls" : "stop"
					chunks = [Response.stream_chunk(**stream_metadata(state), delta: {}, finish_reason: finish_reason)]
					
					if payload.dig("stream_options", "include_usage") && usage = Response.usage(response["usage"])
						chunks << {id: state[:id], object: "chat.completion.chunk", created: state[:created], model: state[:model], choices: [], usage: usage}
					end
					
					return chunks
				when "response.failed", "error"
					message = event.dig("response", "error", "message") || event.dig("error", "message") || "Codex response failed"
					return [{error: {message: message, type: "server_error"}}]
				end
				
				return []
			end
			
			def stream_metadata(state)
				{response_id: state[:id], model: state[:model], created: state[:created]}
			end
			
			def session_id(request)
				Array(request.headers["session-id"]).first || Array(request.headers["x-session-id"]).first || SecureRandom.uuid
			end
			
			def chat_tools?(payload)
				return true if payload["tools"] && !payload["tools"].empty?
				return true if payload["tool_choice"]
				
				Array(payload["messages"]).any? do |message|
					message.is_a?(Hash) && (message["role"] == "tool" || message["tool_calls"])
				end
			end
			
			def error_response(status, message, type)
				body = {error: {message: message, type: type, param: nil, code: nil}}
				Protocol::HTTP::Response[status, {"content-type" => "application/json"}, [JSON.dump(body)]]
			end
		end
	end
end
