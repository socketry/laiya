# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "laiya/version"
require_relative "laiya/models/discover"
require_relative "laiya/configuration"
require_relative "laiya/provider"
require_relative "laiya/provider/interface"
require_relative "laiya/provider/openai"
require_relative "laiya/provider/codex"
require_relative "laiya/provider/ollama"
require_relative "laiya/router"
require_relative "laiya/web/application"

# @namespace
module Laiya
end
