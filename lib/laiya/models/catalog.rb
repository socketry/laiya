# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	module Models
		# Read-only view of configured and provider-backed model catalogs.
		class Catalog
			# Build a catalog view over configuration-owned model data.
			# @parameter routes [Hash(String, Symbol)] Explicit model routes.
			# @parameter sources [Hash(Symbol, Interface(:each, :find))] Provider discovery sources.
			# @parameter metadata [Hash(String, Hash)] Metadata for explicit model routes.
			def initialize(routes:, sources:, metadata:)
				@routes = routes
				@sources = sources
				@metadata = metadata
			end
			
			attr :routes
			attr :sources
			attr :metadata
			
			# Check whether the catalog contains routes or discovery sources.
			# @returns [Boolean] `true` when the catalog is empty.
			def empty?
				@routes.empty? && @sources.empty?
			end
			
			# Check whether the catalog has any provider discovery sources.
			# @returns [Boolean] `true` when discovery is configured.
			def discover?
				!@sources.empty?
			end
			
			# Resolve the provider name for a model, using the default as fallback.
			# @parameter model [String | Nil] The model ID to look up.
			# @option :default_provider [Symbol | Nil] The fallback provider name.
			# @returns [Symbol | Nil] The selected provider name.
			def provider_for(model, default_provider: nil)
				return @routes[model] if @routes.key?(model)
				
				if model
					matches = @sources.filter_map do |provider, source|
						provider if source.find(model)
					end
					
					return default_provider if matches.include?(default_provider)
					return matches.first unless matches.empty?
				end
				
				return default_provider
			end
			
			# Enumerate explicit and discovered models without duplicate IDs.
			# @option :default_provider [Symbol | Nil] The preferred owner of duplicate IDs.
			# @yields {|model| ...} Each model entry in OpenAI model-list format.
			#  @parameter model [Hash] A model-list entry.
			# @returns [Enumerator | Nil] An enumerator without a block, otherwise `nil`.
			def each(default_provider: nil, &block)
				return to_enum(__method__, default_provider: default_provider) unless block
				
				models = {}
				owners = {}
				
				@routes.each do |id, provider|
					models[id] = {
						"id" => id,
						"object" => "model",
						"created" => 0,
						"owned_by" => provider.to_s,
					}.tap do |entry|
						if metadata = @metadata[id]
							entry["laiya"] = metadata
						end
					end
					owners[id] = provider
				end
				
				@sources.each do |provider, source|
					source.each do |model|
						id = model["id"]
						next unless id.is_a?(String) && !id.empty?
						next if @routes.key?(id)
						next if owners.key?(id) && provider != default_provider
						
						models[id] = model.merge("owned_by" => provider.to_s)
						owners[id] = provider
					end
				end
				
				models.each_value(&block)
			end
			
			# Freeze the catalog and its shared configuration data.
			# @returns [Laiya::Models::Catalog] This frozen catalog.
			def freeze
				return self if frozen?
				
				@routes.freeze
				@sources.freeze
				@metadata.freeze
				
				super
			end
		end
	end
end
