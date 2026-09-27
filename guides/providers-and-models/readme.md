# Providers and Models

This guide explains how to route model IDs to providers and when to discover a provider's model catalog.

## Default Provider

Use a default provider when one upstream should receive any model name:

```ruby
configuration = Laiya::Configuration.build do |builder|
	builder.provider :ollama, Laiya::Provider::Ollama.new
	builder.default_provider :ollama
end
```

With no explicit model routes or discovery setting, Laiya forwards
`GET /v1/models` to the default provider and passes completion requests through
to it.

## Discover Models from an Upstream

Providers such as Ollama expose an OpenAI-compatible `GET /v1/models` endpoint.
Use `models: :discover` to query it at runtime instead of copying model names
into configuration:

```ruby
configuration = Laiya::Configuration.build do |builder|
	builder.provider :ollama, Laiya::Provider::Ollama.new, models: :discover
	builder.default_provider :ollama
end
```

`Laiya::Models::Discover` fetches and caches the provider's catalog for 60
seconds. Laiya uses the discovered IDs for `GET /v1/models` and routes requests
for those IDs to the provider. The builder itself does not make network calls.

For multiple providers, enable discovery on each provider. Distinct model IDs
are routed automatically. If two providers advertise the same ID, the default
provider wins; an explicit `builder.model` route overrides discovery:

```ruby
configuration = Laiya::Configuration.build do |builder|
	builder.provider :openai, Laiya::Provider::OpenAI.new(
		api_key: ENV.fetch("OPENAI_API_KEY")
	), models: :discover
	builder.provider :ollama, Laiya::Provider::Ollama.new, models: :discover
	
	builder.model "llama3.2", provider: :ollama
	builder.default_provider :openai
end
```

## Expose Model Limits

OpenAI's standard model-list format has no context-window fields. Laiya lets
you attach a display name and limits to an explicit model route; it publishes
them under its `laiya` extension field:

```ruby
configuration = Laiya::Configuration.build do |builder|
	builder.provider :ollama, Laiya::Provider::Ollama.new, models: :discover
	builder.model "llama3.2",
		provider: :ollama,
		display_name: "Llama 3.2",
		limits: {context: 32_768, input: 28_672, output: 4_096}
	builder.default_provider :ollama
end
```

The `limits` keys are `context`, `input`, and `output`, and values are positive
token counts. OpenCode does not currently infer these custom fields from
`GET /v1/models`; configure its model `limit.context`, `limit.input`, and
`limit.output` values on each client as well. The `context` limit should match
the effective upstream model configuration (for Ollama, including `num_ctx`).

## Customize Discovery

Subclass `Laiya::Models::Discover` to filter models or attach provider-specific
metadata. Override `include_model?` to filter entries and `normalize_model` to
add or adjust model fields:

```ruby
class LocalModels < Laiya::Models::Discover
	protected
	
	def include_model?(model)
		super && model["id"].start_with?("llama")
	end
	
	def normalize_model(model)
		super.merge("laiya" => {"limits" => {"context" => 32_768, "output" => 4_096}})
	end
end

ollama = Laiya::Provider::Ollama.new
configuration = Laiya::Configuration.build do |builder|
	builder.provider :ollama, ollama, models: LocalModels.new(ollama)
	builder.default_provider :ollama
end
```

The model list includes configured IDs and discovered metadata. Custom discovery
metadata is provider-specific and is likewise exposed under Laiya's extension
field; standard clients may ignore it.
