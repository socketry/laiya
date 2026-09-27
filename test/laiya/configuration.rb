# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya"
require "laiya/provider/fake"

describe Laiya::Configuration do
	let(:openai) {Laiya::Provider::Fake.new}
	let(:alternate) {Laiya::Provider::Fake.new}
	
	with ".build" do
		it "returns a mutable configuration when no block is provided" do
			configuration = subject.build
			configuration.provider :openai, openai
			configuration.default_provider = :openai
			
			expect(configuration.providers).to be == {openai: openai}
			expect(configuration.provider_for_model("unknown")).to be_equal(openai)
		end
		
		it "builds a configuration with provider and model routes" do
			configuration = subject.build do |builder|
				builder.provider :openai, openai
				builder.provider :alternate, alternate
				builder.model "gpt-example", provider: :openai, display_name: "GPT Example", limits: {context: 128, input: 96, output: 32}
				builder.model "alternate-model", provider: :alternate
				builder.default_provider :openai
			end
			
			expect(configuration.providers).to be == {openai: openai, alternate: alternate}
			expect(configuration.models.routes).to be == {"gpt-example" => :openai, "alternate-model" => :alternate}
			expect(configuration.models.metadata["gpt-example"]).to be == {
				"name" => "GPT Example",
				"limits" => {"context" => 128, "input" => 96, "output" => 32},
			}
			expect(configuration.provider_for_model("gpt-example")).to be_equal(openai)
			expect(configuration.provider_for_model("unknown")).to be_equal(openai)
		end
		
		it "supports block-scoped builder calls" do
			configuration = subject.build do |builder|
				builder.provider :openai, openai
				builder.default_provider :openai
			end
			
			expect(configuration.default_provider).to be == :openai
		end
		
		it "supports instance-evaluated blocks and always returns the configuration" do
			openai_provider = openai
			configuration = subject.build do
				provider :openai, openai_provider
				default_provider :openai
				:ignored
			end
			
			expect(configuration).to be_a(subject)
			expect(configuration.default_provider).to be == :openai
		end
		
		it "allows an empty configuration" do
			expect(subject.build.providers).to be(:empty?)
		end
		
		it "validates model provider references" do
			expect do
				subject.build do |builder|
					builder.provider :openai, openai
					builder.model "gpt-example", provider: :missing
				end
			end.to raise_exception(ArgumentError)
		end
		
		it "rejects providers that do not implement the provider interface" do
			expect do
				subject.build do |builder|
					builder.provider :invalid, Object.new
				end
			end.to raise_exception(ArgumentError)
		end
		
		it "rejects invalid model sources and default providers" do
			configuration = subject.build
			
			expect do
				configuration.provider :openai, openai, models: Object.new
			end.to raise_exception(ArgumentError)
			expect do
				configuration.default_provider = :missing
			end.to raise_exception(ArgumentError)
		end
		
		it "accepts a custom model catalog source" do
			source = Class.new do
				def each
					yield({"id" => "custom-model"})
				end
				
				def find(id)
					{"id" => id} if id == "custom-model"
				end
			end.new
			configuration = subject.build
			configuration.provider :openai, openai, models: source
			
			expect(configuration.models.sources[:openai]).to be_equal(source)
		end
		
		it "rejects invalid model limits before registering the route" do
			configuration = subject.build
			configuration.provider :openai, openai
			
			expect do
				configuration.model "gpt-example", provider: :openai, limits: {context: -1}
			end.to raise_exception(ArgumentError)
			expect(configuration.models.routes).to be(:empty?)
			expect do
				configuration.model "gpt-example", provider: :openai, limits: []
			end.to raise_exception(ArgumentError)
		end
		
		it "freezes configuration-owned state explicitly" do
			configuration = subject.build do |builder|
				builder.provider :openai, openai
				builder.model "gpt-example", provider: :openai
			end
			builder = Laiya::Configuration::Builder.new(configuration)
			
			expect(configuration.freeze).to be_equal(configuration)
			expect(configuration.freeze).to be_equal(configuration)
			expect do
				builder.provider :alternate, alternate
			end.to raise_exception(FrozenError)
			expect(configuration.providers.frozen?).to be == true
			expect(configuration.models.routes.frozen?).to be == true
		end
	end
end
