# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

source "https://rubygems.org"

gemspec

group :maintenance, optional: true do
	gem "bake-modernize"
	gem "bake-gem-github", "~> 0.6.0"
	gem "bake-releases"
	
	gem "socketry"
	gem "agent-context"
	gem "agent-skills"
	
	gem "decode"
	
	gem "utopia-project"
end

group :test do
	gem "sus"
	gem "covered"
	
	gem "rubocop"
	gem "rubocop-md"
	gem "rubocop-socketry"
	
	gem "sus-fixtures-async"
	gem "sus-fixtures-async-http"
	gem "bake"
	gem "bake-test"
	gem "bake-test-integration"
end
