# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	module Provider
		# Callable provider used by tests and examples.
		class Fake < Interface
			def initialize(response = Protocol::HTTP::Response[200])
				@response = response
				@requests = []
			end
			
			attr :response
			attr :requests
			
			def call(request)
				@requests << request
				raise @response if @response.is_a?(Exception)
				
				return @response
			end
		end
	end
end
