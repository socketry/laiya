# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "configuration/builder"

module Laiya
	# Immutable provider and model routing configuration.
	class Configuration
		def self.build(&block)
			builder = Builder.new
			
			if block.arity == 0
				builder.instance_eval(&block)
			else
				yield builder
			end
			
			return builder.call
		end
		
		def initialize(providers:, models:, default_provider: nil)
			@providers = providers.freeze
			@models = models.freeze
			@default_provider = default_provider
		end
		
		attr :providers
		attr :models
		attr :default_provider
		
		def provider_for_model(model)
			if route = @models[model]
				return @providers.fetch(route)
			elsif @default_provider
				return @providers.fetch(@default_provider)
			end
		end
	end
end
