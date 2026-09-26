# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya"

describe Laiya do
	with ".VERSION" do
		it "starts at 0.0.0" do
			expect(Laiya::VERSION).to be == "0.0.0"
		end
	end
end
