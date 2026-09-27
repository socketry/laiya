# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya/provider/codex"

describe Laiya::Provider::Codex::Response do
	with ".completed" do
		it "returns Codex function calls as OpenAI tool calls for the client to execute" do
			response = subject.completed(
				{
					"id" => "resp_123",
					"model" => "gpt-test",
					"output" => [
						{"type" => "function_call", "call_id" => "call_123", "name" => "weather", "arguments" => "{\"city\":\"Paris\"}"},
					],
					"usage" => {"input_tokens" => 12, "output_tokens" => 3, "total_tokens" => 15},
				},
			)
			
			tool_call = response.dig(:choices, 0, :message, :tool_calls, 0)
			
			expect(response.dig(:choices, 0, :finish_reason)).to be == "tool_calls"
			expect(tool_call[:id]).to be == "call_123"
			expect(tool_call.dig(:function, :name)).to be == "weather"
			expect(tool_call.dig(:function, :arguments)).to be == "{\"city\":\"Paris\"}"
			expect(response.dig(:usage, :total_tokens)).to be == 15
		end
		
		it "serializes structured arguments and generates an ID when Codex omits one" do
			response = subject.completed(
				{
					"output" => [
						{"type" => "function_call", "call_id" => "call_1", "name" => "weather", "arguments" => {"city" => "Paris"}},
					],
				},
			)
			
			arguments = response.dig(:choices, 0, :message, :tool_calls, 0, :function, :arguments)
			expect(JSON.parse(arguments)).to be == {"city" => "Paris"}
			expect(response[:id]).to be =~ /\Achatcmpl-[0-9a-f]+\z/
		end
	end
end
