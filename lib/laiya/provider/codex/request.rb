# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"

module Laiya
	module Provider
		class Codex < Interface
			# Converts OpenAI Chat Completions requests into Codex Responses input.
			module Request
				module_function
				
				# Transform a Chat Completions payload into a Codex Responses request.
				# @parameter payload [Hash] The Chat Completions request object.
				# @returns [Hash] The Codex Responses request payload.
				# @raises [ArgumentError, KeyError] If the request contains unsupported input.
				def transform(payload)
					messages = payload.fetch("messages")
					raise ArgumentError, "messages must be an array" unless messages.is_a?(Array)
					
					instructions = []
					input = []
					
					messages.each do |message|
						raise ArgumentError, "each message must be an object" unless message.is_a?(Hash)
						
						role = message.fetch("role", "user")
						
						case role
						when "system", "developer"
							instructions << text(message.fetch("content", ""))
						when "tool"
							input << {
								type: "function_call_output",
								call_id: message.fetch("tool_call_id"),
								output: text(message.fetch("content", "")),
							}
						else
							raise ArgumentError, "unsupported message role: #{role}" unless %w[user assistant].include?(role)
							
							content = message.fetch("content", "")
							input << {role: role, content: text(content)} unless text(content).empty?
							
							if role == "assistant"
								Array(message["tool_calls"]).each do |tool_call|
									function = tool_call.fetch("function")
									input << {
										type: "function_call",
										call_id: tool_call.fetch("id"),
										name: function.fetch("name"),
										arguments: function.fetch("arguments", "{}"),
									}
								end
							end
						end
					end
					
					result = {
						model: payload.fetch("model"),
						input: input,
						store: false,
						stream: true,
						include: ["reasoning.encrypted_content"],
					}
					
					unless instructions.empty?
						result[:instructions] = instructions.join("\n\n")
					end
					
					%w[parallel_tool_calls temperature top_p].each do |key|
						result[key.to_sym] = payload[key] if payload.key?(key)
					end
					
					if max_tokens = payload["max_completion_tokens"] || payload["max_tokens"]
						result[:max_output_tokens] = max_tokens
					end
					
					if effort = payload["reasoning_effort"]
						result[:reasoning] = {effort: effort, summary: "auto"}
					end
					
					if response_format = transform_response_format(payload["response_format"])
						result[:text] = {format: response_format}
					end
					
					return result
				end
				
				# Convert an OpenAI response format into Codex text formatting options.
				# @parameter format [Hash | Nil] The requested response format.
				# @returns [Hash | Nil] The corresponding Codex format, if provided.
				# @raises [ArgumentError, KeyError] If the format is invalid or unsupported.
				def transform_response_format(format)
					return unless format
					raise ArgumentError, "response_format must be an object" unless format.is_a?(Hash)
					
					case format["type"]
					when "text"
						{type: "text"}
					when "json_object"
						{type: "json_object"}
					when "json_schema"
						schema = format.fetch("json_schema")
						{
							type: "json_schema",
							name: schema.fetch("name"),
						schema: schema.fetch("schema"),
						strict: schema["strict"],
						}.compact
					else
						raise ArgumentError, "unsupported response_format"
					end
				end
				
				# Extract text from supported message content shapes.
				# @parameter content [String | Array | Nil] The message content.
				# @returns [String] The concatenated text content.
				# @raises [ArgumentError] If the content type is unsupported.
				def text(content)
					return "" if content.nil?
					return content if content.is_a?(String)
					
					if content.is_a?(Array)
						return content.filter_map do |part|
							part["text"] if part.is_a?(Hash) && %w[text input_text].include?(part["type"])
						end.join
					end
					
					raise ArgumentError, "only text message content is currently supported"
				end
			end
		end
	end
end
