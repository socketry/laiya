# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "sus/fixtures/async/http"
require "laiya"
require "laiya/provider/fake"

describe "Laiya HTTP API" do
	include Sus::Fixtures::Async::HTTP::ServerContext
	
	def provider
		@provider ||= Laiya::Provider::Fake.new(
			Protocol::HTTP::Response[202, {"content-type" => "application/json"}, ['{"accepted":true}']],
		)
	end
	
	def app
		configuration = Laiya::Configuration.build do |builder|
			builder.provider :fake, provider
			builder.model "configured-model", provider: :fake
		end
		
		Laiya::Web::Application.new(configuration: configuration)
	end
	
	it "routes a request by model and forwards its complete request body" do
		body = JSON.dump(model: "configured-model", messages: [{role: "user", content: "Hello"}], stream: true)
		response = client.post(
			"/v1/chat/completions",
			{"content-type" => "application/json"},
			[body],
		)
		
		expect(response.status).to be == 202
		expect(response.read).to be == '{"accepted":true}'
		expect(provider.requests.length).to be == 1
		expect(provider.requests.first.read).to be == body
	ensure
		response&.close
	end
end
