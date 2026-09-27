# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http"
require "async/service/managed/environment"
require_relative "../configuration"
require_relative "../provider/openai"
require_relative "../service/application"

module Laiya
	# @namespace
	module Environment
		# Default Async::Service environment for the Laiya HTTP API.
		module Application
			include Async::Service::Managed::Environment
			
			# Return the service implementation class.
			# @returns [Class] The Laiya service class.
			def service_class
				Laiya::Service::Application
			end
			
			# Parse the HTTP bind endpoint from the environment.
			# @returns [Async::HTTP::Endpoint] The configured endpoint.
			def endpoint
				Async::HTTP::Endpoint.parse(ENV.fetch("LAIYA_URL", "http://localhost:9292"))
			end
			
			# Run one Laiya service instance.
			# @returns [Integer] The desired service count.
			def count
				1
			end
			
			# Build the default OpenAI-backed configuration.
			# @returns [Laiya::Configuration] The service configuration.
			def configuration
				Laiya::Configuration.build do |builder|
					builder.provider :openai, Laiya::Provider::OpenAI.new
					builder.default_provider :openai
				end
			end
			
			# Build the HTTP application for this environment.
			# @returns [Laiya::Web::Application] The configured API application.
			def application
				Laiya::Web::Application.new(configuration: self.configuration)
			end
		end
	end
end
