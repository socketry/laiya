# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya"
require "laiya/provider/fake"

describe Laiya::Models::Discover do
	let(:catalog_response) do
		models = [
			{id: "llama3.2", object: "model", created: 12, owned_by: "library"},
			{id: "hidden-model", object: "model", created: 13, owned_by: "library"},
		]
		Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [JSON.dump(object: "list", data: models)]]
	end
	let(:provider) {Laiya::Provider::Fake.new(Protocol::HTTP::Response[200], models_response: catalog_response)}
	
	with "#all" do
		it "loads, normalizes, and caches the upstream model catalog" do
			models = subject.new(provider)
			
			expect(models.all.length).to be == 2
			expect(models.find("llama3.2")["id"]).to be == "llama3.2"
			expect(models.all.length).to be == 2
			expect(provider.model_requests).to be == 1
		end
	end
	
	with "a custom discovery source" do
		it "allows subclasses to filter and add model metadata" do
			custom_source = Class.new(subject) do
				protected
				
				def include_model?(model)
					super && model["id"] != "hidden-model"
				end
				
				def normalize_model(model)
					super.merge("context_length" => 32768)
				end
			end.new(provider)
			
			expect(custom_source.all.length).to be == 1
			expect(custom_source.all.first["context_length"]).to be == 32768
		end
	end
	
	with "an invalid provider catalog" do
		it "raises an error for failed HTTP responses" do
			provider = Laiya::Provider::Fake.new(
				Protocol::HTTP::Response[200],
				models_response: Protocol::HTTP::Response[503, {}, ["unavailable"]],
			)
			models = subject.new(provider)
			
			expect{models.all}.to raise_exception(subject::Error)
		end
		
		it "raises an error for malformed or invalid model lists" do
			[
				"not json",
				JSON.dump(error: "missing data"),
				JSON.dump(data: {id: "not-an-array"}),
			].each do |body|
				provider = Laiya::Provider::Fake.new(
					Protocol::HTTP::Response[200],
					models_response: Protocol::HTTP::Response[200, {}, [body]],
				)
				
				expect{subject.new(provider).all}.to raise_exception(subject::Error)
			end
		end
	end
end
