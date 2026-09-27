# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya/provider/codex"

describe Laiya::Provider::Codex::Responses do
	with ".prepare" do
		it "keeps function calls, outputs, and encrypted reasoning in a stateless request" do
			input = [
				{type: "function_call", call_id: "call_1", name: "weather", arguments: "{}"},
				{type: "function_call_output", call_id: "call_1", output: "Sunny"},
				{type: "reasoning", encrypted_content: "opaque"},
			]
			request = subject.prepare({"model" => "gpt-test", "input" => input, "stream" => false})
			
			expect(request["input"]).to be == input
			expect(request["store"]).to be_falsey
			expect(request["stream"]).to be_truthy
			expect(request["include"]).to be(:include?, "reasoning.encrypted_content")
		end
	end
	
	with ".Collector" do
		it "reconstructs a client-visible function call from streamed Codex events" do
			collector = subject::Collector.new
			collector.accept(
				{
					"type" => "response.output_item.added",
					"output_index" => 0,
					"item" => {
						"type" => "function_call",
						"call_id" => "call_1",
						"name" => "weather",
						"arguments" => "",
					},
				},
			)
			collector.accept({"type" => "response.function_call_arguments.delta", "output_index" => 0, "delta" => "{\"city\":\"Paris\"}"})
			
			response = collector.complete({"id" => "resp_1", "output" => []})
			
			expect(response.dig("output", 0, "call_id")).to be == "call_1"
			expect(response.dig("output", 0, "arguments")).to be == "{\"city\":\"Paris\"}"
		end
		
		it "replaces a partial streamed item with its final output item" do
			collector = subject::Collector.new
			collector.accept({"type" => "response.output_item.added", "output_index" => 0, "item" => {"type" => "message", "content" => []}})
			collector.accept({"type" => "response.output_item.done", "output_index" => 0, "item" => {"type" => "message", "content" => [{"type" => "output_text", "text" => "Final"}]}})
			
			response = collector.complete({"output" => []})
			expect(response.dig("output", 0, "content", 0, "text")).to be == "Final"
		end
	end
end
