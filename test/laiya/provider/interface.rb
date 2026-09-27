# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "laiya/provider/interface"

describe Laiya::Provider::Interface do
	it "requires subclasses to implement request forwarding" do
		expect do
			subject.new.call(Protocol::HTTP::Request["GET", "/"])
		end.to raise_exception(NotImplementedError)
	end
end
