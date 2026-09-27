# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	class Configuration
		# Mutable DSL for configuring a Laiya::Configuration.
		class Builder
			def initialize(configuration)
				@configuration = configuration
			end
			
			def provider(name, instance, models: nil)
				@configuration.provider(name, instance, models: models)
			end
			
			def model(name, provider:, display_name: nil, limits: nil)
				@configuration.model(name, provider: provider, display_name: display_name, limits: limits)
			end
			
			def default_provider(name)
				@configuration.default_provider = name
			end
		end
	end
end
