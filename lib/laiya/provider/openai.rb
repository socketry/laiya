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
			
			# Initialize a provider for OpenAI or another compatible endpoint.
			# @option :api_key [String | Nil] The bearer token for the upstream service.
			# @option :endpoint [String | Async::HTTP::Endpoint] The upstream HTTP endpoint.
			# @option :client [Interface(:call) | Nil] An optional externally managed HTTP client.
			# @option :organization [String | Nil] An optional OpenAI organization ID.
			# @option :project [String | Nil] An optional OpenAI project ID.
			def initialize(api_key: ENV["OPENAI_API_KEY"], endpoint: DEFAULT_ENDPOINT, client: nil, organization: nil, project: nil, **client_options)
				@endpoint = Async::HTTP::Endpoint[endpoint]
				@api_key = api_key
				@organization = organization
				@project = project
				@client = client || Async::HTTP::Client.new(@endpoint, **client_options)
				@owns_client = client.nil?
			end
			
			attr :endpoint
			
			# Fetch the upstream model-list response.
			# @returns [Protocol::HTTP::Response] The raw model-list response.
			# Fetch the upstream OpenAI-compatible model list as a raw HTTP response.
			def models
				self.call(Protocol::HTTP::Request["GET", "/v1/models"])
			end
			
			# Forward a request without transforming its body.
			# @parameter request [Protocol::HTTP::Request] The request to send upstream.
			# @returns [Protocol::HTTP::Response] The unmodified upstream response.
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
			
			# Close the HTTP client when this provider created it.
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
