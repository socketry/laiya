# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya/provider/openai"
require "sus/fixtures/async/http"

describe Laiya::Provider::OpenAI do
	let(:headers) {Protocol::HTTP::Headers.new}
	let(:response) {Protocol::HTTP::Response[200, {}, ["upstream"]]}
	let(:client) do
		Class.new do
			attr :requests
			
			def initialize(response)
				@response = response
				@requests = []
			end
			
			def call(request)
				@requests << request
				return @response
			end
		end.new(response)
	end
	let(:provider) {subject.new(api_key: "secret", organization: "org", project: "project", client: client)}
	
	with "#call" do
		it "passes the HTTP body and streaming response through and sets provider headers" do
			body = Protocol::HTTP::Body::Buffered.new(["request-body"])
			headers.add("content-type", "application/json")
			headers.add("authorization", "Bearer client-token")
			headers.add("host", "laiya.example")
			headers.add("connection", "x-hop, keep-alive")
			headers.add("x-hop", "remove-me")
			request = Protocol::HTTP::Request.new(nil, nil, "POST", "/v1/chat/completions", "HTTP/1.1", headers, body)
			
			result = provider.call(request)
			forwarded = client.requests.first
			
			expect(result).to be_equal(response)
			expect(forwarded.body).to be_equal(body)
			expect(forwarded.path).to be == "/v1/chat/completions"
			expect(forwarded.headers["authorization"]).to be == "Bearer secret"
			expect(Array(forwarded.headers["openai-organization"]).first).to be == "org"
			expect(Array(forwarded.headers["openai-project"]).first).to be == "project"
			expect(forwarded.headers["host"]).to be_nil
			expect(forwarded.headers["connection"]).to be_nil
			expect(forwarded.headers["x-hop"]).to be_nil
		end
	end
end

describe "OpenAI provider HTTP forwarding" do
	include Sus::Fixtures::Async::HTTP::ServerContext
	
	def app
		Protocol::HTTP::Middleware.for(&method(:receive_request))
	end
	
	def receive_request(request)
		@received = {
			method: request.method,
			path: request.path,
			authorization: request.headers["authorization"],
			body: request.read,
		}
		
		Protocol::HTTP::Response[206, {"content-type" => "text/plain"}, ["streamed upstream body"]]
	end
	
	attr :received
	
	def before
		super
		
		@provider = Laiya::Provider::OpenAI.new(
			api_key: "test-token",
			endpoint: Async::HTTP::Endpoint.parse(bound_url),
		)
	end
	
	def after(error = nil)
		@provider&.close
		
		super
	end
	
	it "forwards an HTTP request and returns its response without transforming the body" do
		body = '{"model":"test-model","stream":true}'
		request = Protocol::HTTP::Request[
			"POST",
			"/v1/chat/completions",
			{"content-type" => "application/json"},
			[body],
		]
		
		response = @provider.call(request)
		
		expect(response.status).to be == 206
		expect(response.read).to be == "streamed upstream body"
		expect(received).to be == {
			method: "POST",
			path: "/v1/chat/completions",
			authorization: "Bearer test-token",
			body: body,
		}
	ensure
		response&.close
	end
end
