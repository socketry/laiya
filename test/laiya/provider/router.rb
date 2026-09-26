# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya"
require "laiya/provider/fake"

describe Laiya::Provider::Router do
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
end
