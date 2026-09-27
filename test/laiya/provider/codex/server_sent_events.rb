# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya/provider/codex"

describe Laiya::Provider::Codex::ServerSentEvents do
	with ".each" do
		it "decodes named events and ignores the terminal marker" do
			body = [
				"event: response.completed\n",
				"data: {\"response\":{\"id\":\"resp_1\"}}\n\n",
				"data: [DONE]\n\n",
			]
			events = subject.each(body).to_a
			
			expect(events).to have_attributes(length: be == 1)
			expect(events.first["type"]).to be == "response.completed"
		end
		
		it "parses a final event without a terminating newline" do
			events = subject.parse(['data: {"type":"response.completed"}'])
			
			expect(events.first["type"]).to be == "response.completed"
		end
		
		it "accepts a final event-name line without data" do
			expect(subject.each(["event: response.completed"]).to_a).to be(:empty?)
		end
		
		it "uses an event name for final data without a terminating newline" do
			events = subject.each(["event: response.completed\n", "data: {\"id\":\"resp_1\"}"]).to_a
			expect(events.first).to be == {"id" => "resp_1", "type" => "response.completed"}
		end
	end
end
