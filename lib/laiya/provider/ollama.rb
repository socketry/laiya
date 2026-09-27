# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

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
		end
	end
end
