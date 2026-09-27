# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	class Configuration
		# Mutable DSL for configuring a Laiya::Configuration.
		class Builder
			# Attach a DSL builder to the configuration it will update.
			# @parameter configuration [Laiya::Configuration] The mutable configuration.
			def initialize(configuration)
				@configuration = configuration
			end
			
			# Configure a provider on the attached configuration.
			# @parameter name [String | Symbol] The provider's routing name.
			# @parameter instance [Interface(:call)] The provider implementation.
			# @option :models [Symbol | Interface(:each, :find) | Nil] The model source or `:discover`.
			def provider(name, instance, models: nil)
				@configuration.provider(name, instance, models: models)
			end
			
			# Configure a model route on the attached configuration.
			# @parameter name [String | Symbol] The model ID.
			# @parameter provider [String | Symbol] The provider name.
			# @option :display_name [String | Nil] A human-readable model name.
			# @option :limits [Hash | Nil] Positive context, input, and output token limits.
			def model(name, provider:, display_name: nil, limits: nil)
				@configuration.model(name, provider: provider, display_name: display_name, limits: limits)
			end
			
			# Set the default provider on the attached configuration.
			# @parameter name [String | Symbol] The provider name.
			def default_provider(name)
				@configuration.default_provider = name
			end
		end
	end
end
