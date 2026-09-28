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
		it "discovers OpenAI-compatible models with named and boolean thinking metadata" do
			catalog = Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [JSON.dump(
				object: "list",
				data: [
					{id: "qwen3:latest", object: "model", owned_by: "library"},
					{id: "gpt-oss:20b", object: "model", owned_by: "library"},
					{id: "llama3.2:latest", object: "model", owned_by: "library"},
					{},
				],
			)]]
			thinking = {
				"qwen3:latest" => {thinking: {values: ["low", "medium", "high", "", nil, "medium"], default: "medium"}},
				"gpt-oss:20b" => {thinking: {values: [false, true], default: true}},
				"llama3.2:latest" => {thinking: {values: [false], default: false}},
			}
			client = Class.new do
				attr :requests
				attr :models
				
				def initialize(catalog, thinking)
					@catalog = catalog
					@thinking = thinking
					@requests = []
					@models = []
				end
				
				def call(request)
					@requests << request
					return @catalog if request.path == "/v1/models"
					
					model = JSON.parse(request.read).fetch("model")
					@models << model
					return Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [JSON.dump(@thinking.fetch(model))]]
				end
			end.new(catalog, thinking)
			provider = subject.new(client: client)
			
			response = provider.models
			result = JSON.parse(response.read).fetch("data")
			
			expect(response.status).to be == 200
			expect(client.requests.map(&:path)).to be == ["/v1/models", "/api/show", "/api/show", "/api/show"]
			expect(client.requests[1].headers["authorization"]).to be == "Bearer ollama"
			expect(client.models).to be == ["qwen3:latest", "gpt-oss:20b", "llama3.2:latest"]
			expect(result[0].dig("laiya", "reasoning")).to be == {
				"thinking_values" => ["low", "medium", "high"],
				"default_thinking" => "medium",
				"supported_efforts" => ["low", "medium", "high"],
				"default_effort" => "medium",
			}
			expect(result[1].dig("laiya", "reasoning")).to be == {
				"thinking_values" => [false, true],
				"default_thinking" => true,
			}
			expect(result[2].key?("laiya")).to be == false
			expect(result[3]).to be == {}
		ensure
			response&.close
			provider&.close
		end
		
		it "keeps models when thinking metadata is absent or unavailable" do
			catalog = Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [JSON.dump(
				data: [
					{id: "plain-model"},
					{id: "unavailable-model"},
				],
			)]]
			client = Class.new do
				def initialize(catalog)
					@catalog = catalog
				end
				
				def call(request)
					return @catalog if request.path == "/v1/models"
					
					model = JSON.parse(request.read).fetch("model")
					return Protocol::HTTP::Response[500] if model == "unavailable-model"
					
					Protocol::HTTP::Response[200, {"content-type" => "application/json"}, ['{"thinking":{"values":[]}}']]
				end
			end.new(catalog)
			provider = subject.new(client: client)
			
			response = provider.models
			result = JSON.parse(response.read).fetch("data")
			
			expect(result).to be == [{"id" => "plain-model"}, {"id" => "unavailable-model"}]
		ensure
			response&.close
			provider&.close
		end
		
		it "preserves model catalogs returned with an error status" do
			client = Class.new do
				def initialize(response)
					@response = response
				end
				
				def call(_request)
					@response
				end
			end.new(Protocol::HTTP::Response[401])
			provider = subject.new(client: client)
			
			response = provider.models
			expect(response.status).to be == 401
		ensure
			response&.close
			provider&.close
		end
		
		it "returns a server error for an invalid catalog shape" do
			client = Class.new do
				def call(_request)
					Protocol::HTTP::Response[200, {"content-type" => "application/json"}, ['{"data":{}}']]
				end
			end.new
			provider = subject.new(client: client)
			
			response = provider.models
			
			expect(response.status).to be == 502
			expect(JSON.parse(response.read).dig("error", "message")).to be == "Ollama model catalog was invalid"
		ensure
			response&.close
			provider&.close
		end
		
		it "keeps a model when querying its thinking metadata fails" do
			catalog = Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [JSON.dump(data: [{id: "model"}])]]
			client = Class.new do
				def initialize(catalog)
					@catalog = catalog
				end
				
				def call(request)
					return @catalog if request.path == "/v1/models"
					
					raise IOError, "Ollama is unavailable"
				end
			end.new(catalog)
			provider = subject.new(client: client)
			
			response = provider.models
			
			expect(JSON.parse(response.read).fetch("data")).to be == [{"id" => "model"}]
		ensure
			response&.close
			provider&.close
		end
		
		it "rejects invalid model catalog responses" do
			client = Class.new do
				def initialize(body)
					@body = body
				end
				
				def call(_request)
					Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [@body]]
				end
			end.new("not json")
			provider = subject.new(client: client)
			
			response = provider.models
			
			expect(response.status).to be == 502
			expect(JSON.parse(response.read).dig("error", "message")).to be == "Ollama model catalog was invalid"
		ensure
			response&.close
			provider&.close
		end
		
		it "queries Ollama's OpenAI-compatible model list for an empty catalog" do
			result = provider.models
			request = client.requests.first
			
			expect(result.status).to be == 200
			expect(JSON.parse(result.read).fetch("data")).to be(:empty?)
			expect(request.method).to be == "GET"
			expect(request.path).to be == "/v1/models"
			expect(request.headers["authorization"]).to be == "Bearer ollama"
		ensure
			result&.close
			provider&.close
		end
	end
end
