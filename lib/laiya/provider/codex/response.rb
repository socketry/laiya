# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"
require "securerandom"

module Laiya
	module Provider
		class Codex < Interface
			# Converts Codex Responses API results into OpenAI Chat Completions.
			module Response
				module_function
				
				def completed(response, requested_model: nil)
					output = response.fetch("output", [])
					content = []
					tool_calls = []
					
					output.each do |item|
						case item["type"]
						when "message"
							Array(item["content"]).each do |part|
								content << part["text"] if part["type"] == "output_text" && part["text"]
								content << part["refusal"] if part["type"] == "refusal" && part["refusal"]
							end
						when "function_call"
							tool_calls << {
								id: item["call_id"] || item["id"],
								type: "function",
								function: {
									name: item["name"],
									arguments: json_arguments(item["arguments"]),
								},
							}
						end
					end
					
					message = {role: "assistant", content: content.empty? ? nil : content.join}
					message[:tool_calls] = tool_calls unless tool_calls.empty?
					usage = usage(response["usage"])
					result = {
						id: completion_id(response["id"]),
						object: "chat.completion",
						created: response["created_at"] || Time.now.to_i,
						model: response["model"] || requested_model,
						choices: [{index: 0, message: message, finish_reason: tool_calls.empty? ? "stop" : "tool_calls"}],
					}
					result[:usage] = usage if usage
					
					return result
				end
				
				def stream_chunk(response_id:, model:, created:, delta:, finish_reason: nil, usage: nil)
					chunk = {
						id: completion_id(response_id),
						object: "chat.completion.chunk",
						created: created || Time.now.to_i,
						model: model,
						choices: [{index: 0, delta: delta, finish_reason: finish_reason}],
					}
					chunk[:usage] = usage if usage
					return chunk
				end
				
				def usage(value)
					return unless value.is_a?(Hash)
					
					input_tokens = value["input_tokens"]
					output_tokens = value["output_tokens"]
					return unless input_tokens && output_tokens
					
					{
						prompt_tokens: input_tokens,
						completion_tokens: output_tokens,
						total_tokens: value["total_tokens"] || input_tokens + output_tokens,
						prompt_tokens_details: {cached_tokens: value.dig("input_tokens_details", "cached_tokens") || 0},
					}
				end
				
				def json_arguments(arguments)
					return arguments if arguments.is_a?(String)
					
					JSON.dump(arguments || {})
				end
				
				def completion_id(response_id)
					return "chatcmpl-#{response_id}" if response_id
					
					"chatcmpl-#{SecureRandom.hex(12)}"
				end
			end
		end
	end
end
