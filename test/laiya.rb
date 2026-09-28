# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya"

describe Laiya do
	with ".VERSION" do
		it "uses a semantic version" do
			expect(Laiya::VERSION).to be =~ /\A\d+\.\d+\.\d+\z/
		end
	end
end
