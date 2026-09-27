# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"
require "json"

module Laiya
	# Model catalog sources.
	module Models
		# Discovers models from an OpenAI-compatible provider and caches its catalog.
		# Subclasses can filter or enrich entries by overriding #include_model? and #normalize_model.
		class Discover
			DEFAULT_TTL = 60
			
			def initialize(provider, ttl: DEFAULT_TTL)
				@provider = provider
				@ttl = ttl
				@lock = Async::Semaphore.new(1)
				@models = nil
				@expires_at = 0
			end
			
			attr :provider
			
			def each(&block)
				return enum_for(__method__) unless block
				
				self.all.each(&block)
			end
			
			def find(id)
				self.all.find{|model| model["id"] == id}
			end
			
			def all
				if @models && Process.clock_gettime(Process::CLOCK_MONOTONIC) < @expires_at
					return @models
				end
				
				@lock.acquire do
					now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
					next @models if @models && now < @expires_at
					
					@models = fetch_models.freeze
					@expires_at = now + @ttl
				end
				
				return @models
			end
			
			protected
			
			def include_model?(model)
				model.is_a?(Hash) && model["id"].is_a?(String) && !model["id"].empty?
			end
			
			def normalize_model(model)
				result = model.dup
				result["object"] ||= "model"
				result["created"] ||= 0
				return result.freeze
			end
			
			private
			
			def fetch_models
				response = @provider.models
				unless response.status >= 200 && response.status < 300
					status = response.status
					response.close
					raise Error, "Model discovery failed with HTTP #{status}"
				end
				
				begin
					payload = JSON.parse(response.read)
					data = payload.fetch("data")
					unless data.is_a?(Array)
						raise Error, "Model discovery returned an invalid catalog"
					end
					
					return data.filter_map do |model|
						self.normalize_model(model) if self.include_model?(model)
					end
				rescue JSON::ParserError, KeyError
					raise Error, "Model discovery returned an invalid catalog"
				ensure
					response.close
				end
			end
			
			class Error < StandardError
			end
		end
	end
end
