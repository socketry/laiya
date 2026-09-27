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
	end
end
