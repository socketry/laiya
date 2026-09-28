# frozen_string_literal: true

require_relative "lib/laiya/version"

Gem::Specification.new do |spec|
	spec.name = "laiya"
	spec.version = Laiya::VERSION
	
	spec.summary = "An OpenAI-compatible HTTP API and provider proxy"
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/socketry-release.pem")
	
	spec.homepage = "https://github.com/socketry/laiya"
	
	spec.metadata = {
		"bug_tracker_uri" => "https://github.com/socketry/laiya/issues",
		"changelog_uri" => "https://github.com/socketry/laiya/blob/main/releases.md",
		"documentation_uri" => "https://socketry.github.io/laiya/",
		"source_code_uri" => "https://github.com/socketry/laiya.git",
	}
	
	spec.files = Dir.glob(["{bin,context,examples,guides,lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__).reject do |path|
		path == "agents.md"
	end
	
	spec.executables = ["laiya"]
	
	spec.required_ruby_version = ">= 3.3"
	
	spec.add_dependency "async"
	spec.add_dependency "async-http"
	spec.add_dependency "async-service"
	spec.add_dependency "base64"
end
