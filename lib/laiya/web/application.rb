# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "protocol/http/middleware"
require_relative "../router"

module Laiya
	# @namespace
	module Web
		# OpenAI-compatible HTTP API application.
		class Application < Protocol::HTTP::Middleware
			# Initialize the API middleware with a configuration.
			# @parameter configuration [Laiya::Configuration] Provider and model routing settings.
			def initialize(configuration:)
				@configuration = configuration
				@router = Laiya::Router.new(configuration)
			end
			
			attr :configuration
			
			# Handle a model-list request or proxy a request to its provider.
			# @parameter request [Protocol::HTTP::Request] The incoming HTTP request.
			# @returns [Protocol::HTTP::Response] The API response.
			def call(request)
				if request.method == "GET" && request.path == "/v1/models" && (response = @router.models_response)
					return response
				end
				
				return @router.call(request)
			rescue StandardError
				return Protocol::HTTP::Response[
					502,
					{"content-type" => "application/json"},
					[JSON.dump(error: {message: "Upstream provider request failed", type: "server_error"})],
				]
			end
			
			# Close all providers owned by the application.
			def close
				@router.close
			end
			
		end
	end
end
