# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya"
require "laiya/provider/fake"

describe Laiya::Web::Application do
	let(:provider) {Laiya::Provider::Fake.new}
	let(:configuration) do
		Laiya::Configuration.build do |builder|
			builder.provider :fake, provider
			builder.model "configured-model", provider: :fake
			builder.default_provider :fake
		end
	end
	let(:application) {subject.new(configuration: configuration)}
	
	with "#call" do
		it "forwards requests through the configured router" do
			request = Protocol::HTTP::Request["GET", "/v1/other"]
			
			expect(application.call(request)).to be_equal(provider.response)
			expect(provider.requests.first).to be_equal(request)
		end
		
		it "lists configured models using the OpenAI model list shape" do
			request = Protocol::HTTP::Request["GET", "/v1/models"]
			configuration = Laiya::Configuration.build do |builder|
				builder.provider :fake, provider
				builder.model "configured-model", provider: :fake
			end
			application = subject.new(configuration: configuration)
			
			response = application.call(request)
			payload = JSON.parse(response.read)
			
			expect(response.status).to be == 200
			expect(payload.dig("data", 0, "id")).to be == "configured-model"
			expect(provider.requests).to be(:empty?)
		end
		
		it "returns an OpenAI-compatible error when the provider raises" do
			provider = Laiya::Provider::Fake.new(IOError.new("connection failed"))
			configuration = Laiya::Configuration.build do |builder|
				builder.provider :fake, provider
				builder.default_provider :fake
			end
			application = subject.new(configuration: configuration)
			
			response = application.call(Protocol::HTTP::Request["GET", "/v1/models"])
			
			expect(response.status).to be == 502
			expect(JSON.parse(response.read).dig("error", "type")).to be == "server_error"
		end
	end
end
