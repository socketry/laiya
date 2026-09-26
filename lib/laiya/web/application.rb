# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "protocol/http/middleware"
require_relative "../provider/router"

module Laiya
	module Web
		# OpenAI-compatible HTTP API application.
		class Application < Protocol::HTTP::Middleware
			def initialize(configuration:)
				@configuration = configuration
				@router = Provider::Router.new(configuration)
			end
			
			attr :configuration
			
			def call(request)
				if request.method == "GET" && request.path == "/v1/models" && !@configuration.models.empty?
					return models_response
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
			
			private
			
			def models_response
				models = @configuration.models.map do |name, provider|
					{ id: name, object: "model", created: 0, owned_by: provider.to_s }
				end
				
				Protocol::HTTP::Response[
					200,
					{"content-type" => "application/json"},
					[JSON.dump(object: "list", data: models)],
				]
			end
		end
	end
end
