# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http"
require "async/service/managed/service"
require_relative "../web/application"

module Laiya
	# @namespace
	module Service
		# Runs the Laiya API application on Async::HTTP::Server.
		class Application < Async::Service::Managed::Service
			# Bind the service endpoint when the service starts.
			# @returns [Nil] The result of the superclass start hook.
			def start
				super
				
				@endpoint = @evaluator.endpoint
				@bound_endpoint = Sync{@endpoint.bound}
			end
			
			# Close the bound endpoint and API application when stopping.
			# @returns [Nil] The result of the superclass stop hook.
			def stop
				@bound_endpoint&.close
				@application&.close
				
				super
			end
			
			# Run one Async HTTP server instance.
			# @parameter instance [Object] The managed service instance.
			# @parameter evaluator [Object] The service environment evaluator.
			# @returns [Object] The running HTTP server task.
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
