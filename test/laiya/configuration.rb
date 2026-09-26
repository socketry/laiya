# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya"
require "laiya/provider/fake"

describe Laiya::Configuration do
	let(:openai) {Laiya::Provider::Fake.new}
	let(:alternate) {Laiya::Provider::Fake.new}
	
	with ".build" do
		it "builds a configuration with provider and model routes" do
			configuration = subject.build do |builder|
				builder.provider :openai, openai
				builder.provider :alternate, alternate
				builder.model "gpt-example", provider: :openai
				builder.model "alternate-model", provider: :alternate
				builder.default_provider :openai
			end
			
			expect(configuration.providers).to be == {openai: openai, alternate: alternate}
			expect(configuration.models).to be == {"gpt-example" => :openai, "alternate-model" => :alternate}
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
		
		it "requires at least one provider" do
			expect{subject.build{}}.to raise_exception(ArgumentError)
		end
		
		it "validates model provider references" do
			expect do
				subject.build do |builder|
					builder.provider :openai, openai
					builder.model "gpt-example", provider: :missing
				end
			end.to raise_exception(ArgumentError)
		end
	end
end
