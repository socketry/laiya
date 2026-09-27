# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya/provider/ollama"

describe Laiya::Provider::Ollama do
	let(:response) {Protocol::HTTP::Response[200, {}, ['{"data":[]}']]}
	let(:client) do
		Class.new do
			attr :requests
			
			def initialize(response)
				@response = response
				@requests = []
			end
			
			def call(request)
				@requests << request
				@response
			end
		end.new(response)
	end
	let(:provider) {subject.new(client: client)}
	
	it "defaults to the local Ollama OpenAI-compatible endpoint" do
		expect(provider.endpoint.authority).to be == "localhost:11434"
	end
	
	with "#models" do
		it "queries Ollama's OpenAI-compatible model list without parsing the response" do
			result = provider.models
			request = client.requests.first
			
			expect(result).to be_equal(response)
			expect(request.method).to be == "GET"
			expect(request.path).to be == "/v1/models"
			expect(request.headers["authorization"]).to be == "Bearer ollama"
		end
	end
end
