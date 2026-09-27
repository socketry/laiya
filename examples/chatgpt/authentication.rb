# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "openssl"
require "protocol/http/middleware"

module Examples
	module ChatGPT
		# Requires a local API key before forwarding to the personal Codex account.
		class Authentication < Protocol::HTTP::Middleware
			def initialize(delegate, token:)
				super(delegate)
				raise ArgumentError, "LAIYA_API_KEY must not be empty" if token.empty?
				
				@token = token
			end
			
			def call(request)
				scheme, supplied = request.headers["authorization"].to_s.split(" ", 2)
				
				unless valid_token?(scheme, supplied)
					return Protocol::HTTP::Response[
						401,
						{"content-type" => "application/json", "www-authenticate" => "Bearer"},
						[JSON.dump(error: {message: "Invalid API key", type: "authentication_error"})],
					]
				end
				
				return @delegate.call(request)
			end
			
			private
			
			def valid_token?(scheme, supplied)
				return false unless scheme == "Bearer" && supplied
				return false unless supplied.bytesize == @token.bytesize
				
				OpenSSL.fixed_length_secure_compare(supplied, @token)
			end
		end
	end
end
