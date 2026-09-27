# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "protocol/http/middleware"
require_relative "../router"

module Laiya
	module Web
		# OpenAI-compatible HTTP API application.
		class Application < Protocol::HTTP::Middleware
			def initialize(configuration:)
				@configuration = configuration
				@router = Laiya::Router.new(configuration)
			end
			
			attr :configuration
			
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
			
			def close
				@router.close
			end
			
		end
	end
end
