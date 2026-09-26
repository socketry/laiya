# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/http"
require_relative "interface"

module Laiya
	module Provider
		# Forwards OpenAI-compatible HTTP requests to the OpenAI API.
		class OpenAI < Interface
			DEFAULT_ENDPOINT = "https://api.openai.com"
			HOP_BY_HOP_HEADERS = %w[
				connection
				keep-alive
				proxy-authenticate
				proxy-authorization
				te
				trailer
				transfer-encoding
				upgrade
			].freeze
			
			def initialize(api_key: ENV["OPENAI_API_KEY"], endpoint: DEFAULT_ENDPOINT, client: nil, organization: nil, project: nil, **client_options)
				@endpoint = Async::HTTP::Endpoint[endpoint]
				@api_key = api_key
				@organization = organization
				@project = project
				@client = client || Async::HTTP::Client.new(@endpoint, **client_options)
				@owns_client = client.nil?
			end
			
			attr :endpoint
			
			def call(request)
				headers = forwarded_headers(request.headers)
				headers["authorization"] = "Bearer #{@api_key}" if @api_key
				headers["openai-organization"] = @organization if @organization
				headers["openai-project"] = @project if @project
				
				upstream_request = Protocol::HTTP::Request.new(
					@endpoint.scheme,
					@endpoint.authority,
					request.method,
					request.path,
					request.version,
					headers,
					request.body,
					request.protocol,
					request.interim_response,
				)
				
				return @client.call(upstream_request)
			end
			
			def close
				@client.close if @owns_client
			end
			
			private
			
			def forwarded_headers(headers)
				forwarded = headers.dup
				connection_headers = Array(headers["connection"]).flat_map{|value| value.split(",")}.map(&:strip)
				
				(HOP_BY_HOP_HEADERS + connection_headers + ["host"]).uniq.each do |name|
					forwarded.delete(name)
				end
				
				return forwarded
			end
		end
	end
end
