# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"

require_relative "openai"

module Laiya
	module Provider
		# Proxies Ollama's OpenAI-compatible HTTP API.
		class Ollama < OpenAI
			DEFAULT_ENDPOINT = "http://localhost:11434"
			
			# Initialize a provider with Ollama's local endpoint and API-key default.
			# @option :endpoint [String | Async::HTTP::Endpoint] The Ollama HTTP endpoint.
			# @option :api_key [String | Nil] The optional bearer token.
			def initialize(endpoint: DEFAULT_ENDPOINT, api_key: "ollama", **options)
				super(endpoint: endpoint, api_key: api_key, **options)
			end
			
			# Fetch Ollama's model list and add supported thinking metadata.
			# @returns [Protocol::HTTP::Response] The enriched OpenAI-compatible model list.
			def models
				response = super
				return response unless response.status >= 200 && response.status < 300
				
				enrich_models(response)
			end
			
			private
			
			def enrich_models(response)
				payload = JSON.parse(response.read)
				models = payload.fetch("data")
				unless models.is_a?(Array)
					return model_catalog_error
				end
				
				payload["data"] = models.map{|model| enrich_model(model)}
				return Protocol::HTTP::Response[
					200,
					{"content-type" => "application/json"},
					[JSON.dump(payload)],
				]
			rescue JSON::ParserError, KeyError, TypeError
				model_catalog_error
			ensure
				response.close
			end
			
			def enrich_model(model)
				return model unless model.is_a?(Hash)
				return model unless model["id"].is_a?(String) && !model["id"].empty?
				
				response = self.call(Protocol::HTTP::Request[
					"POST",
					"/api/show",
					{"content-type" => "application/json"},
					[JSON.dump(model: model["id"])],
				])
				return model unless response.status >= 200 && response.status < 300
				
				thinking = JSON.parse(response.read)["thinking"]
				reasoning = normalize_reasoning(thinking)
				return model unless reasoning
				
				metadata = model["laiya"].is_a?(Hash) ? model["laiya"].dup : {}
				metadata["reasoning"] = reasoning
				return model.merge("laiya" => metadata)
			rescue StandardError
				return model
			ensure
				response&.close
			end
			
			def normalize_reasoning(thinking)
				return unless thinking.is_a?(Hash)
				
				values = Array(thinking["values"]).select do |value|
					(value.is_a?(String) && !value.empty?) || value == true || value == false
				end.uniq
				return if values.empty? || values == [false]
				
				result = {"thinking_values" => values}
				default = thinking["default"]
				result["default_thinking"] = default if values.include?(default)
				
				efforts = values.grep(String)
				unless efforts.empty?
					result["supported_efforts"] = efforts
					result["default_effort"] = default if efforts.include?(default)
				end
				
				return result
			end
			
			def model_catalog_error
				Protocol::HTTP::Response[
					502,
					{"content-type" => "application/json"},
					[JSON.dump(error: {message: "Ollama model catalog was invalid", type: "server_error"})],
				]
			end
		end
	end
end
