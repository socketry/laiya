# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	module Provider
		class Codex < Interface
			# Applies the Codex-specific settings while preserving the Responses API payload.
			module Responses
				module_function
				
				def prepare(payload)
					if payload["previous_response_id"]
						raise ArgumentError, "Codex stateless mode requires the client to send full input history"
					end
					
					result = payload.dup
					result["store"] = false
					result["stream"] = true
					
					include_items = Array(result["include"])
					include_items << "reasoning.encrypted_content" unless include_items.include?("reasoning.encrypted_content")
					result["include"] = include_items
					
					return result
				end
				
				# Rebuilds output items from streamed events when the terminal Codex
				# response omits them (some Codex responses return an empty output array).
				class Collector
					def initialize
						@items = {}
					end
					
					def accept(event)
						case event["type"]
						when "response.output_item.added"
							@items[event.fetch("output_index", @items.length)] = duplicate(event.fetch("item"))
						when "response.output_text.delta", "response.refusal.delta"
							append_text(event)
						when "response.function_call_arguments.delta"
							append_arguments(event)
						when "response.output_item.done"
							@items[event.fetch("output_index", @items.length)] = duplicate(event.fetch("item"))
						end
					end
					
					def complete(response)
						unless response["output"].is_a?(Array) && !response["output"].empty?
							response["output"] = @items.sort_by{|index, _item| index}.map(&:last)
						end
						
						return response
					end
					
					private
					
					def append_text(event)
						index = event.fetch("output_index", 0)
						item = @items[index] ||= {"type" => "message", "role" => "assistant", "content" => []}
						content_index = event.fetch("content_index", 0)
						part = item.fetch("content")
						part[content_index] ||= {"type" => event["type"] == "response.refusal.delta" ? "refusal" : "output_text", "text" => ""}
						key = event["type"] == "response.refusal.delta" ? "refusal" : "text"
						part[content_index][key] = part[content_index].fetch(key, "") + event.fetch("delta", "")
					end
					
					def append_arguments(event)
						index = event.fetch("output_index", 0)
						item = @items[index] ||= {"type" => "function_call", "arguments" => ""}
						item["arguments"] = item.fetch("arguments", "") + event.fetch("delta", "")
						item["id"] ||= event["item_id"]
					end
					
					def duplicate(value)
						JSON.parse(JSON.dump(value))
					end
				end
			end
		end
	end
end
