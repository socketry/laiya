# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http"
require "async/service/managed/environment"
require_relative "../configuration"
require_relative "../provider/openai"
require_relative "../service/application"

module Laiya
	module Environment
		# Default Async::Service environment for the Laiya HTTP API.
		module Application
			include Async::Service::Managed::Environment
			
			def service_class
				Laiya::Service::Application
			end
			
			def endpoint
				Async::HTTP::Endpoint.parse(ENV.fetch("LAIYA_URL", "http://localhost:9292"))
			end
			
			def count
				1
			end
			
			def configuration
				Laiya::Configuration.build do |builder|
					builder.provider :openai, Laiya::Provider::OpenAI.new
					builder.default_provider :openai
				end
			end
			
			def application
				Laiya::Web::Application.new(configuration: self.configuration)
			end
		end
	end
end
