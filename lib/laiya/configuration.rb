# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "models/catalog"
require_relative "models/discover"
require_relative "configuration/builder"

module Laiya
	# Mutable provider and model routing configuration.
	class Configuration
		# Build a mutable configuration by evaluating a builder block.
		# @yields {|builder| ...} The builder used to configure the new object.
		# @parameter builder [Laiya::Configuration::Builder] The configuration DSL.
		# @returns [Laiya::Configuration] The configured, mutable object.
		def self.build(&block)
			configuration = self.new
			builder = Builder.new(configuration)
			
			if block
				if block.arity.zero?
					builder.instance_eval(&block)
				else
					block.call(builder)
				end
			end
			
			return configuration
		end
		
		# Initialize an empty provider and model catalog.
		def initialize
			@providers = {}
			@model_routes = {}
			@model_sources = {}
			@model_metadata = {}
			@models = Models::Catalog.new(
				routes: @model_routes,
				sources: @model_sources,
				metadata: @model_metadata,
			)
			@default_provider = nil
		end
		
		attr :providers
		attr :models
		attr :default_provider
		
		# Register a provider and optionally a model source.
		# @parameter name [String | Symbol] The provider's routing name.
		# @parameter instance [Interface(:call)] The provider implementation.
		# @option :models [Symbol | Interface(:each, :find) | Nil] The model source or `:discover`.
		# @raises [ArgumentError] If the provider or model source is invalid.
		def provider(name, instance, models: nil)
			name = name.to_sym
			raise ArgumentError, "Provider #{name.inspect} is already configured" if @providers.key?(name)
			
			unless instance.respond_to?(:call)
				raise ArgumentError, "Provider #{name.inspect} must respond to #call"
			end
			
			case models
			when nil, :configured
				# Model routes will be configured separately with #model.
			when :discover
				@model_sources[name] = Models::Discover.new(instance)
			else
				unless models.respond_to?(:each) && models.respond_to?(:find)
					raise ArgumentError, "Model source for provider #{name.inspect} must implement #each and #find"
				end
				
				@model_sources[name] = models
			end
			
			@providers[name] = instance
		end
		
		# Route a model ID to a configured provider and attach optional metadata.
		# @parameter name [String | Symbol] The model ID.
		# @parameter provider [String | Symbol] The provider name.
		# @option :display_name [String | Nil] A human-readable model name.
		# @option :limits [Hash | Nil] Positive context, input, and output token limits.
		# @raises [ArgumentError] If the provider, model ID, or limits are invalid.
		def model(name, provider:, display_name: nil, limits: nil)
			provider = provider.to_sym
			unless @providers.key?(provider)
				raise ArgumentError, "Provider #{provider.inspect} for model #{name.inspect} is not configured"
			end
			
			name = name.to_s
			raise ArgumentError, "Model #{name.inspect} is already configured" if @model_routes.key?(name)
			
			metadata = {}
			metadata["name"] = display_name.to_s if display_name
			metadata["limits"] = normalize_limits(limits) if limits
			
			@model_routes[name] = provider
			@model_metadata[name] = metadata.freeze unless metadata.empty?
		end
		
		# Set the provider used when no explicit or discovered route matches.
		# @parameter name [String | Symbol | Nil] The provider name, or `nil` to clear the default.
		# @raises [ArgumentError] If the provider is not configured.
		def default_provider=(name)
			name = name&.to_sym
			if name && !@providers.key?(name)
				raise ArgumentError, "Default provider #{name.inspect} is not configured"
			end
			
			@default_provider = name
		end
		
		# Find the provider instance that serves a model ID.
		# @parameter model [String | Nil] The model ID to route.
		# @returns [Interface(:call) | Nil] The matching provider, if any.
		def provider_for_model(model)
			if name = @models.provider_for(model, default_provider: @default_provider)
				return @providers.fetch(name)
			end
		end
		
		# Freeze configuration-owned state and finalize this object.
		# @returns [Laiya::Configuration] This frozen configuration.
		def freeze
			return self if frozen?
			
			@providers.freeze
			@models.freeze
			
			super
		end
		
		private
		
		def normalize_limits(limits)
			unless limits.is_a?(Hash)
				raise ArgumentError, "Model limits must be a Hash"
			end
			
			allowed = %w[context input output]
			limits.each_with_object({}) do |(key, value), normalized|
				key = key.to_s
				unless allowed.include?(key) && value.is_a?(Integer) && value.positive?
					raise ArgumentError, "Invalid model limit #{key.inspect}: #{value.inspect}"
				end
				
				normalized[key] = value
			end.freeze
		end
	end
end
