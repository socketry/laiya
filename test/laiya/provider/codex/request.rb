# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya/provider/codex"

describe Laiya::Provider::Codex::Request do
	with ".transform" do
		it "maps text Chat Completions messages to Responses input" do
			request = subject.transform(
				"model" => "gpt-test",
				"messages" => [
					{"role" => "system", "content" => "Be concise."},
					{"role" => "user", "content" => "Hello"},
				],
			)
			
			expect(request[:instructions]).to be == "Be concise."
			expect(request[:input].first).to be == {role: "user", content: "Hello"}
			expect(request[:stream]).to be == true
			expect(request[:store]).to be == false
		end
		
		it "converts tool history, token limits, reasoning, and response format" do
			request = subject.transform(
				"model" => "gpt-test",
				"messages" => [
					{"role" => "tool", "tool_call_id" => "call_1", "content" => "Sunny"},
					{"role" => "assistant", "content" => "", "tool_calls" => [
						{"id" => "call_2", "function" => {"name" => "weather", "arguments" => "{}"}},
					]},
				],
				"max_tokens" => 64,
				"reasoning_effort" => "high",
				"response_format" => {"type" => "json_schema", "json_schema" => {"name" => "answer", "schema" => {"type" => "object"}, "strict" => true}},
			)
			
			expect(request[:input]).to be == [
				{type: "function_call_output", call_id: "call_1", output: "Sunny"},
				{type: "function_call", call_id: "call_2", name: "weather", arguments: "{}"},
			]
			expect(request[:max_output_tokens]).to be == 64
			expect(request[:reasoning]).to be == {effort: "high", summary: "auto"}
			expect(request[:text][:format][:name]).to be == "answer"
		end
	end
	
	with ".transform_response_format" do
		it "maps text and JSON object response formats" do
			expect(subject.transform_response_format({"type" => "text"})).to be == {type: "text"}
			expect(subject.transform_response_format({"type" => "json_object"})).to be == {type: "json_object"}
		end
		
		it "rejects response formats it cannot transform" do
			expect{subject.transform_response_format("json")}.to raise_exception(ArgumentError)
			expect{subject.transform_response_format({"type" => "unknown"})}.to raise_exception(ArgumentError)
		end
	end
	
	with ".text" do
		it "extracts text blocks and rejects non-text content" do
			content = [
				{"type" => "input_text", "text" => "Hello"},
				{"type" => "image_url", "url" => "ignored"},
				{"type" => "text", "text" => " world"},
			]
			
			expect(subject.text(content)).to be == "Hello world"
			expect{subject.text({"type" => "image"})}.to raise_exception(ArgumentError)
		end
	end
end
