# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	class Configuration
		# Mutable DSL for constructing a runtime configuration.
		class Builder
			def initialize
				@providers = {}
				@models = {}
				@default_provider = nil
			end
			
			def provider(name, instance)
				name = name.to_sym
				raise ArgumentError, "Provider #{name.inspect} is already configured" if @providers.key?(name)
				
				@providers[name] = instance
			end
			
			def model(name, provider:)
				name = name.to_s
				raise ArgumentError, "Model #{name.inspect} is already configured" if @models.key?(name)
				
				@models[name] = provider.to_sym
			end
			
			def default_provider(name)
				@default_provider = name.to_sym
			end
			
			def call
				if @providers.empty?
					raise ArgumentError, "At least one provider must be configured"
				end
				
				@providers.each do |name, provider|
					unless provider.respond_to?(:call)
						raise ArgumentError, "Provider #{name.inspect} must respond to #call"
					end
				end
				
				if @default_provider && !@providers.key?(@default_provider)
					raise ArgumentError, "Default provider #{@default_provider.inspect} is not configured"
				end
				
				@models.each do |model, provider|
					unless @providers.key?(provider)
						raise ArgumentError, "Provider #{provider.inspect} for model #{model.inspect} is not configured"
					end
				end
				
				Configuration.new(
					providers: @providers.dup,
					models: @models.dup,
					default_provider: @default_provider,
				)
			end
		end
	end
end
