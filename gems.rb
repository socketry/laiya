# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

source "https://rubygems.org"

gemspec

group :maintenance, optional: true do
	gem "agent-context"
	gem "bake-gem"
	gem "bake-modernize"
	gem "bake-releases"
	gem "decode"
	gem "utopia-project"
end

group :test do
	gem "sus"
	gem "covered"
	gem "rubocop"
	gem "rubocop-socketry"
	gem "sus-fixtures-async"
	gem "sus-fixtures-async-http"
	gem "bake"
	gem "bake-test"
end

gem "rubocop-md", "~> 2.0", group: :test
