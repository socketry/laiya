# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	module Provider
		# Base interface for OpenAI-compatible HTTP providers.
		class Interface
			# Forward an HTTP request to the provider.
			# @parameter request [Protocol::HTTP::Request] The request to forward.
			# @returns [Protocol::HTTP::Response] The upstream response.
			# @raises [NotImplementedError] When a subclass does not implement this method.
			def call(request)
				raise NotImplementedError
			end
		end
	end
end
