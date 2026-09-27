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
