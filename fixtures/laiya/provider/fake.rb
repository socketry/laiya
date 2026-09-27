# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	module Provider
		# Callable provider used by tests and examples.
		class Fake < Interface
			def initialize(response = Protocol::HTTP::Response[200], models_response: nil)
				@response = response
				@models_response = models_response
				@model_requests = 0
				@requests = []
			end
			
			attr :response
			attr :model_requests
			attr :requests
			
			def call(request)
				@requests << request
				raise @response if @response.is_a?(Exception)
				
				return @response
			end
			
			def models
				@model_requests += 1
				return @models_response
			end
		end
	end
end
