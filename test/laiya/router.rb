# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya"
require "laiya/provider/fake"

describe Laiya::Router do
	let(:response) {Protocol::HTTP::Response[201, {"x-upstream" => "true"}, ["response"]]}
	let(:openai) {Laiya::Provider::Fake.new(response)}
	let(:alternate) {Laiya::Provider::Fake.new}
	let(:configuration) do
		Laiya::Configuration.build do |builder|
			builder.provider :openai, openai
			builder.provider :alternate, alternate
			builder.model "model-a", provider: :openai
			builder.model "model-b", provider: :alternate
			builder.default_provider :openai
		end
	end
	let(:router) {subject.new(configuration)}
	
	with "model-based routing" do
		it "selects the provider configured for the requested model and rewinds the body" do
			body = '{"model":"model-b","messages":[]}'
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				[body],
			]
			
			result = router.call(request)
			
			expect(result).to be_equal(alternate.response)
			expect(alternate.requests.length).to be == 1
			expect(alternate.requests.first.read).to be == body
			expect(openai.requests).to be(:empty?)
		end
	end
	
	with "default routing" do
		it "routes non-model endpoints to the default provider" do
			request = Protocol::HTTP::Request["GET", "/v1/models"]
			
			expect(router.call(request)).to be_equal(response)
			expect(openai.requests).to have_attributes(length: be == 1)
		end
		
		it "uses the default provider when the model request body is malformed" do
			body = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				["not json"],
			]
			
			expect(router.call(body)).to be_equal(response)
			expect(openai.requests.first.read).to be == "not json"
		end
	end
	
	with "missing default provider" do
		it "returns an OpenAI-compatible not found error" do
			configuration = Laiya::Configuration.build do |builder|
				builder.provider :openai, openai
				builder.model "model-a", provider: :openai
			end
			request = Protocol::HTTP::Request["GET", "/v1/models"]
			
			result = subject.new(configuration).call(request)
			
			expect(result.status).to be == 404
			expect(JSON.parse(result.read).dig("error", "type")).to be == "not_found_error"
		end
	end
	
	with "upstream model discovery" do
		it "lists and routes discovered models without registering them individually" do
			models_response = Protocol::HTTP::Response[
				200,
				{"content-type" => "application/json"},
				[JSON.dump(object: "list", data: [{id: "llama3.2", object: "model", created: 12, owned_by: "library"}])],
			]
			ollama = Laiya::Provider::Fake.new(response, models_response: models_response)
			configuration = Laiya::Configuration.build do |builder|
				builder.provider :ollama, ollama, models: :discover
			end
			router = subject.new(configuration)
			expect(configuration.models.discover?).to be == true
			
			listed = router.models_response
			payload = JSON.parse(listed.read)
			request = Protocol::HTTP::Request[
				"POST",
				"/v1/chat/completions",
				{"content-type" => "application/json"},
				['{"model":"llama3.2","messages":[]}'],
			]
			forwarded_response = router.call(request)
			
			expect(payload.dig("data", 0, "id")).to be == "llama3.2"
			expect(payload.dig("data", 0, "owned_by")).to be == "ollama"
			expect(forwarded_response).to be_equal(response)
			expect(ollama.model_requests).to be == 1
			expect(ollama.requests.length).to be == 1
		end
	end
	
	with "closing providers" do
		it "closes unique providers that support closing" do
			provider = Class.new do
				attr :close_count
				
				def initialize
					@close_count = 0
				end
				
				def call(_request)
				end
				
				def close
					@close_count += 1
				end
			end.new
			configuration = Laiya::Configuration.build do |builder|
				builder.provider :first, provider
				builder.provider :second, provider
			end
			
			subject.new(configuration).close
			
			expect(provider.close_count).to be == 1
		end
	end
end
