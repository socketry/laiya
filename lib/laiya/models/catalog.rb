# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

module Laiya
	module Models
		# Read-only view of configured and provider-backed model catalogs.
		class Catalog
			def initialize(routes:, sources:, metadata:)
				@routes = routes
				@sources = sources
				@metadata = metadata
			end
			
			attr :routes
			attr :sources
			attr :metadata
			
			def empty?
				@routes.empty? && @sources.empty?
			end
			
			def discover?
				!@sources.empty?
			end
			
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
