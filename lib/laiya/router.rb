# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"

module Laiya
	# Selects a configured provider for each OpenAI-compatible HTTP request.
	class Router
		MODEL_ENDPOINTS = %w[
			/v1/chat/completions
			/v1/completions
			/v1/embeddings
			/v1/responses
			/v1/images/generations
		].freeze
		
		def initialize(configuration)
			@configuration = configuration
		end
		
		def call(request)
			provider = provider_for_model(model_for(request))
			
			unless provider
				return Protocol::HTTP::Response[
					404,
					{"content-type" => "application/json"},
					[JSON.dump(error: {message: "No provider is configured for this request", type: "not_found_error"})],
				]
			end
			
			return provider.call(request)
		end
		
		# Return the configured model catalog, if present.
		def models_response
			return if @configuration.models.empty?
			models = @configuration.models.each(default_provider: @configuration.default_provider).to_a
			
			Protocol::HTTP::Response[
				200,
				{"content-type" => "application/json"},
				[JSON.dump(object: "list", data: models)],
			]
		end
		
		def close
			@configuration.providers.values.uniq.each do |provider|
				provider.close if provider.respond_to?(:close)
			end
		end
		
		private
		
		def provider_for_model(model)
			return @configuration.provider_for_model(model)
		end
		
		def model_for(request)
			return unless request.method == "POST" && MODEL_ENDPOINTS.include?(request.path.split("?", 2).first)
			return unless request.headers["content-type"]&.start_with?("application/json")
			return unless request.body
			
			request.buffered!
			
			begin
				body = request.body.chunks.join
				payload = JSON.parse(body)
				payload["model"] if payload.is_a?(Hash)
			rescue JSON::ParserError, TypeError
				nil
			ensure
				request.rewind!
			end
		end
	end
end
