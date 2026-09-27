# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http"
require "async/service/managed/service"
require_relative "../web/application"

module Laiya
	module Service
		# Runs the Laiya API application on Async::HTTP::Server.
		class Application < Async::Service::Managed::Service
			def start
				super
				
				@endpoint = @evaluator.endpoint
				@bound_endpoint = Sync{@endpoint.bound}
			end
			
			def stop
				@bound_endpoint&.close
				@application&.close
				
				super
			end
			
			def run(instance, evaluator)
				@application = evaluator.application
				server = Async::HTTP::Server.new(
					@application,
					@bound_endpoint,
					protocol: @endpoint.protocol,
					scheme: @endpoint.scheme,
				)
				
				return server.run
			end
		end
	end
end
