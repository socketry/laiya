# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	module Provider
		# Base interface for OpenAI-compatible HTTP providers.
		class Interface
			def call(request)
				raise NotImplementedError
			end
		end
	end
end
