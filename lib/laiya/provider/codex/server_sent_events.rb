# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "json"

module Laiya
	module Provider
		class Codex < Interface
			# Incrementally decodes Codex Responses API server-sent events.
			module ServerSentEvents
				module_function
				
				# Decode an HTTP body as server-sent events.
				# @parameter body [Enumerable(String)] The streamed event body.
				# @yields {|event| ...} Each decoded event.
				#  @parameter event [Hash] The event data.
				# @returns [Enumerator | Nil] An enumerator without a block, otherwise `nil`.
				def each(body, &block)
					return enum_for(__method__, body) unless block
					
					buffer = String.new
					data = []
					event_name = nil
					
					body.each do |chunk|
						buffer << chunk
						while newline = buffer.index("\n")
							line = buffer.slice!(0, newline + 1).delete_suffix("\n").delete_suffix("\r")
							
							if line.empty?
								yield_event(event_name, data, &block) unless data.empty?
								data.clear
								event_name = nil
							elsif line.start_with?("data:")
								data << line.delete_prefix("data:").sub(/\A /, "")
							elsif line.start_with?("event:")
								event_name = line.delete_prefix("event:").strip
							end
						end
					end
					
					unless buffer.empty?
						line = buffer.delete_suffix("\r")
						data << line.delete_prefix("data:").sub(/\A /, "") if line.start_with?("data:")
						event_name = line.delete_prefix("event:").strip if line.start_with?("event:")
					end
					
					yield_event(event_name, data, &block) unless data.empty?
				end
				
				# Collect all decoded events from a body.
				# @parameter body [Enumerable(String)] The event body.
				# @returns [Array(Hash)] The decoded events.
				def parse(body)
					events = []
					each(body) {|event| events << event}
					return events
				end
				
				# Parse event data and yield a non-terminal event.
				# @parameter event_name [String | Nil] The optional event name.
				# @parameter data [Array(String)] The event data lines.
				# @yields {|event| ...} The parsed event object.
				# @parameter event [Hash] The decoded JSON data.
				def yield_event(event_name, data)
					joined = data.join("\n")
					return if joined == "[DONE]"
					
					event = JSON.parse(joined)
					event["type"] ||= event_name if event_name
					yield event
				end
			end
		end
	end
end
