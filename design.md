# Laiya Design

Laiya is a Ruby gem for presenting a unified, OpenAI-compatible interface to one or more large language model providers. It is inspired by LiteLLM, but should feel idiomatic in Ruby and integrate naturally with the Socketry async ecosystem.

## Goals

- Use OpenAI-compatible HTTP as Laiya's canonical protocol for chat, completions, embeddings, model listing, and future LLM capabilities.
- Include a built-in `Laiya::Provider::OpenAI` provider.
- Define a provider abstraction under `Laiya::Provider` so providers behave like OpenAI-compatible HTTP endpoints.
- Support multiple configured providers and model routes.
- Use `Async::HTTP` internally for non-blocking HTTP I/O.
- Later, provide an idiomatic, richer Ruby client API as a separate convenience layer over the OpenAI-compatible HTTP protocol.
- Expose an OpenAI-compatible HTTP API for clients that already speak OpenAI's REST API.
- Support both direct Ruby usage and deployment as a proxy/gateway service.

## Non-goals for the first implementation

- Full LiteLLM feature parity.
- Every OpenAI API endpoint.
- An independent provider-neutral LLM schema separate from OpenAI's API shape.
- Provider-specific prompt or response normalization for all vendors beyond what is required to satisfy OpenAI-compatible requests.
- Persistent configuration stores, billing, quotas, or user management.
- A Rails dependency.
- Response parsing or body transformation in the proxy path.
- A Rack-based server interface.

## Namespace and top-level layout

The gem should use the `Laiya` namespace.

Proposed initial file layout:

```text
bin/
  laiya
lib/
  laiya.rb
  laiya/version.rb
  laiya/configuration.rb
  laiya/configuration/builder.rb
  laiya/provider.rb
  laiya/provider/interface.rb
  laiya/provider/router.rb
  laiya/provider/openai.rb
  laiya/web.rb
  laiya/web/application.rb
  laiya/environment/application.rb
  laiya/service/api.rb
```

The public namespaces should include:

```ruby
module Laiya
end

module Laiya::Provider
end

class Laiya::Provider::OpenAI
end
```

## Provider abstraction

Providers should expose a common HTTP-shaped interface using `Protocol::HTTP::Request` and `Protocol::HTTP::Response` directly. The canonical request and response format is OpenAI-compatible HTTP: method, path, headers, and body in; status, headers, and body out.

This gives Laiya a simple symmetry:

```text
OpenAI-compatible HTTP client
        |
        v
Laiya OpenAI-compatible web API
        |
        v
Laiya provider HTTP interface
        |
        v
OpenAI-compatible or translated upstream provider
```

For OpenAI itself, `Laiya::Provider::OpenAI` should be a direct proxy. It should forward requests and responses without parsing, normalizing, or transforming bodies. For non-OpenAI providers, a separate translating provider may adapt between OpenAI-compatible HTTP requests and the upstream provider's native API.

The initial provider interface should be intentionally small and endpoint-agnostic:

```ruby
module Laiya::Provider
	class Interface
		def call(request)
			raise NotImplementedError
		end
	end
end
```

`request` should be a `Protocol::HTTP::Request`, not a Laiya-specific proxy wrapper or an LLM-specific abstraction:

```ruby
request = Protocol::HTTP::Request[
	"POST",
	"/v1/chat/completions",
	[["content-type", "application/json"]],
	[JSON.dump(model: "gpt-4.1-mini", messages: [{role: "user", content: "Hello!"}])]
]

response = provider.call(request)
```

The response should likewise be a `Protocol::HTTP::Response`:

```ruby
response.status  # 200
response.headers # Protocol::HTTP::Headers-compatible headers
response.body    # HTTP body, passed through without proxy-side processing
```

`Laiya::Provider::OpenAI` should implement this interface by forwarding OpenAI-compatible requests to OpenAI's API without inspecting or processing the request or response body. Later providers can implement the same interface by translating OpenAI-compatible requests into provider-specific HTTP calls and translating responses back into OpenAI-compatible responses.

### Future Ruby client API

The richer Ruby API should be treated as a separate client layer, not part of the proxy design. It can be built later around OpenAI's existing resource shape rather than an independent Laiya schema. It should be a convenience layer that constructs OpenAI-compatible HTTP requests, invokes an HTTP endpoint/provider, parses responses, and wraps OpenAI-compatible response bodies.

Target resource-oriented API:

```ruby
client = Laiya::Client.new(provider: Laiya::Provider::OpenAI.new)

response = client.chat.completions.create(
	model: "gpt-4.1-mini",
	messages: [
		{role: "user", content: "Hello!"}
	]
)

puts response.choices.first.message.content

models = client.models.list
```

This API should mirror OpenAI's organization where practical:

- `client.chat.completions.create(...)` -> `POST /v1/chat/completions`
- `client.models.list` -> `GET /v1/models`
- `client.embeddings.create(...)` -> `POST /v1/embeddings`
- `client.responses.create(...)` -> `POST /v1/responses`

The structured Ruby objects should provide predictable accessors over parsed OpenAI-compatible response bodies while preserving original metadata. These are convenience objects for the future Ruby client API, not the proxy transport type.

Examples:

- `Laiya::Chat::Completion`
- `Laiya::Chat::CompletionChoice`
- `Laiya::Chat::Message`
- `Laiya::Model`

Simple Hash input can be accepted by the future client API because it maps naturally to OpenAI JSON payloads. The proxy itself should not parse or normalize those payloads unless a translation provider explicitly needs to do so.

Example direct usage target:

```ruby
client = Laiya::Client.new(
	provider: Laiya::Provider::OpenAI.new(api_key: ENV.fetch("OPENAI_API_KEY"))
)

response = client.chat.completions.create(
	model: "gpt-4.1-mini",
	messages: [
		{role: "user", content: "Hello!"}
	]
)

puts response.choices.first.message.content
```

## HTTP client design

Provider implementations should use `Async::HTTP` internally. The core provider call path should preserve HTTP semantics and bodies as much as possible:

```text
Protocol::HTTP::Request  ->  provider.call  ->  Protocol::HTTP::Response
```

For OpenAI-compatible upstream providers, this should be implemented as a direct proxy with no JSON parsing, body buffering, or response wrapping in the proxy path:

```text
POST /v1/chat/completions
  -> Laiya::Provider::OpenAI
  -> POST https://api.openai.com/v1/chat/completions
```

For translated upstream providers, the same interface is preserved:

```text
POST /v1/chat/completions
  -> Laiya::Provider::Anthropic
  -> POST https://api.anthropic.com/v1/messages
  -> OpenAI-compatible response
```

The lower-level HTTP design can still borrow operational ideas from `async-ollama`, while keeping the proxy path raw:

- A small provider client object owns the endpoint and request behavior.
- Request methods dispatch HTTP requests with `Async::HTTP`.
- Request and response bodies are forwarded directly for proxy providers.
- Parsing/wrapping belongs in a separate Ruby client layer, not in the proxy provider.

`async-ollama` currently uses `Async::REST::Resource` and `Async::REST::Representation` on top of `Async::HTTP`. Laiya can use a similar approach later for a richer Ruby client API if it remains a good fit, while keeping the provider/proxy API centered on raw `Protocol::HTTP::Request` and `Protocol::HTTP::Response` pass-through.

Expected dependencies:

- `async`
- `async-http`
- `async-service` for the API service launcher and supervision model
- `protocol-http` for request/response objects and middleware-style application boundaries, if not already provided transitively

Future client-layer dependencies:

- optionally `async-rest` if a later Ruby client adopts the `async-ollama` resource/representation pattern

### OpenAI provider client

`Laiya::Provider::OpenAI` should be the built-in OpenAI-compatible provider. It may delegate to an internal HTTP client, e.g. `Laiya::Provider::OpenAI::Client`.

Responsibilities:

- Configure API endpoint, defaulting to `https://api.openai.com`.
- Configure authorization using `OPENAI_API_KEY` or an explicit `api_key:`.
- Forward OpenAI-compatible methods, paths, headers, and bodies to the upstream endpoint.
- Set or override authorization and other provider-owned headers.
- Preserve OpenAI response status, headers, and body without parsing.
- Avoid unnecessary request/response transformation when upstream is already OpenAI-compatible.
- Support streaming later by forwarding Server-Sent Events without unnecessary buffering.

The provider itself may be low-level and HTTP-shaped. The richer `Laiya::Client` API should avoid leaking low-level HTTP concerns for normal Ruby usage.

## Configuration

Laiya should use a first-class `Laiya::Configuration` object to describe the available providers, model routes, default provider/model behavior, and API service settings. The HTTP API application should receive a configuration object, not a single provider.

Configuration should be built with `Laiya::Configuration::Builder`:

```ruby
configuration = Laiya::Configuration.build do |builder|
	builder.provider :openai, Laiya::Provider::OpenAI.new(
		api_key: ENV.fetch("OPENAI_API_KEY")
	)

	builder.provider :openai_compatible, Laiya::Provider::OpenAI.new(
		endpoint: Async::HTTP::Endpoint.parse("https://api.example.com"),
		api_key: ENV.fetch("EXAMPLE_API_KEY")
	)

	builder.model "gpt-4.1-mini", provider: :openai
	builder.model "example/small", provider: :openai_compatible

	builder.default_provider :openai
end

app = Laiya::Web::Application.new(configuration: configuration)
```

The builder should provide a concise DSL while producing an immutable or effectively immutable configuration object for runtime use.

Proposed API:

```ruby
class Laiya::Configuration
	def self.build(&block)
		builder = Builder.new
		yield builder
		builder.call
	end

	attr :providers
	attr :models
	attr :default_provider

	def provider_for_model(model)
		# Returns the provider for a configured route or default.
	end
end

class Laiya::Configuration::Builder
	def provider(name, instance)
	end

	def model(name, provider:)
	end

	def default_provider(name)
	end

	def call
	end
end
```

Model configuration should support at least:

- public model name accepted by Laiya, e.g. `"gpt-4.1-mini"`.
- provider name, e.g. `:openai`.
- optional metadata for future routing/fallback decisions.

For direct OpenAI-compatible proxying, routing may need to inspect the request body to choose a provider by model. That inspection should be limited to routing and must not transform the body.

When model-based routing is enabled for known JSON endpoints, the router uses `Protocol::HTTP::Request#buffered!` to make the request body rewindable before inspection:

```ruby
request.buffered!

body = request.body
payload = JSON.parse(body.chunks.join)
model = payload["model"] if payload.is_a?(Hash)

request.rewind!
provider = configuration.provider_for_model(model)
provider.call(request)
```

The important rule is that request-body buffering is a routing concern only. The router buffers and inspects request bodies for known OpenAI-compatible JSON endpoints, then rewinds and forwards the same body. Model alias rewriting is not part of the initial implementation.

Configuration should be explicit and environment-friendly:

OpenAI provider configuration:

- `api_key:` or `OPENAI_API_KEY`
- `endpoint:` defaulting to `https://api.openai.com`
- `organization:` optional
- `project:` optional
- request timeout options later

The initial implementation supports a default provider plus explicit model routes. More advanced fallback/load-balancing behavior can be added later.

## OpenAI-compatible HTTP API

Laiya should expose an HTTP API that accepts OpenAI-compatible `Protocol::HTTP::Request` objects, forwards them through the configured Laiya routing layer, and returns the resulting `Protocol::HTTP::Response` to the HTTP client.

Because the provider interface is already OpenAI-compatible HTTP, the HTTP API should be thin:

```text
incoming HTTP request
  -> provider.call(request)
  -> outgoing HTTP response
```

Initial endpoints:

- `GET /v1/models`
- `POST /v1/chat/completions`

When explicit model routes are configured, `GET /v1/models` returns that configured model list in OpenAI's response shape. With no explicit model routes, it is forwarded to the default provider.

Potential later endpoints:

- `POST /v1/completions`
- `POST /v1/embeddings`
- `POST /v1/responses`
- `POST /v1/images/generations`

The HTTP API should:

- Accept OpenAI-compatible HTTP requests.
- Return OpenAI-compatible HTTP responses.
- Preserve error status codes where practical.
- Preserve streaming responses where practical.
- Avoid parsing, buffering, or transforming request/response bodies in the direct proxy path.
- Be implemented directly on `Async::HTTP::Server` and `Protocol::HTTP` request/response objects.
- Be runnable as an `Async::Service`, similar to Lively's `bin/lively` launcher pattern.
- Avoid Rack as a primary or compatibility target.

`Laiya::Web::Application` should be a callable HTTP application, similar in shape to Lively's application middleware:

```ruby
class Laiya::Web::Application
	def initialize(configuration:)
		@configuration = configuration
		@router = Laiya::Provider::Router.new(configuration)
	end

	def call(request)
		@router.call(request)
	end
end
```

The service entry point should use `Async::Service::Configuration` and `Async::Service::Controller.run`, in the same spirit as Lively's `bin/lively`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "async/service"
require "laiya/environment/application"

ARGV.each do |path|
	require(path)
end

configuration = Async::Service::Configuration.build do
	service "laiya" do
		include Laiya::Environment::Application
	end
end

Async::Service::Controller.run(configuration)
```

`Laiya::Environment::Application` should provide the service configuration needed to bind an endpoint, build the `Laiya::Configuration`, build the `Laiya::Web::Application`, and run it using `Async::HTTP::Server` directly.

The exact API can be refined during implementation, but the intended shape is:

```ruby
module Laiya::Environment::Application
	def endpoint
		Async::HTTP::Endpoint.parse(ENV.fetch("LAIYA_URL", "http://localhost:9292"))
	end

	def count
		1
	end

	def configuration
		Laiya::Configuration.build do |builder|
			builder.provider :openai, Laiya::Provider::OpenAI.new(api_key: ENV.fetch("OPENAI_API_KEY"))
			builder.default_provider :openai
		end
	end

	def application
		Laiya::Web::Application.new(configuration: self.configuration)
	end

	def run
		server = Async::HTTP::Server.new(self.application, self.endpoint)
		server.run
	end
end
```

Example target usage:

```ruby
configuration = Laiya::Configuration.build do |builder|
	builder.provider :openai, Laiya::Provider::OpenAI.new(api_key: ENV.fetch("OPENAI_API_KEY"))
	builder.default_provider :openai
end

app = Laiya::Web::Application.new(configuration: configuration)
```

## Provider routing

Provider routing should be driven by `Laiya::Configuration`. The router should be a callable provider-like object:

```ruby
router = Laiya::Provider::Router.new(configuration)
response = router.call(request)
```

Here, `request` and `response` are `Protocol::HTTP::Request` and `Protocol::HTTP::Response` objects.

The router selects the configured provider for each request. The initial implementation supports:

- default provider routing when no specific model route matches.
- explicit model routes from `Laiya::Configuration`.

Provider/model prefixes such as `openai/gpt-4.1-mini` and fallback/load-balancing policies are future extensions.

For model-based routing, the router calls `request.buffered!` for known JSON endpoints before inspecting the `model` field, then calls `request.rewind!` before forwarding the request to the selected provider. Response bodies are not buffered or parsed by the router.

Possible routing examples:

- `gpt-4.1-mini` -> OpenAI provider by default.
- `openai/gpt-4.1-mini` -> OpenAI provider explicitly.
- `anthropic/claude-*` -> future Anthropic provider.
- `ollama/llama3.2` -> future Ollama provider.

Example configuration:

```ruby
configuration = Laiya::Configuration.build do |builder|
	builder.provider :openai, Laiya::Provider::OpenAI.new(api_key: ENV.fetch("OPENAI_API_KEY"))
	builder.provider :fast, Laiya::Provider::OpenAI.new(endpoint: Async::HTTP::Endpoint.parse("https://api.fast.example"))

	builder.model "gpt-4.1-mini", provider: :openai
	builder.model "fast", provider: :fast

	builder.default_provider :openai
end
```

Routing should happen before provider translation. For example, a request body with `model: "anthropic/claude-sonnet-4"` can route to an Anthropic provider, which then translates the OpenAI-compatible `/v1/chat/completions` request into Anthropic's native API.

For pure proxy providers, routing preserves the request body. Model aliases that require rewriting `model` are not supported in the initial implementation.

## Streaming

Streaming should be planned from the beginning, even if the first implementation only supports non-streaming requests.

OpenAI chat streaming uses Server-Sent Events. Since OpenAI-compatible HTTP is the canonical protocol, streaming should remain OpenAI-compatible at the provider boundary.

For OpenAI itself, streaming should be forwarded directly without parsing SSE frames. For translated providers, native streaming events may need to be converted into OpenAI-compatible SSE chunks.

Laiya should eventually expose streaming in three ways:

1. Provider API: return/forward an HTTP streaming body.
2. Ruby API: yield structured chunks parsed from OpenAI-compatible SSE.
3. Web API: forward OpenAI-compatible SSE chunks.

Any streaming parser design should belong to either translating providers or a future Ruby client API. The direct OpenAI proxy should preserve streaming bodies without parsing them.

## Error handling

Upstream HTTP responses, including provider error responses, should be forwarded without changing their status, headers, or body. Transport or provider-call exceptions should be returned as a generic `502` response in OpenAI's error shape, without exposing internal exception details:

```json
{
  "error": {
    "message": "Upstream provider request failed",
    "type": "server_error",
    "param": null,
    "code": null
  }
}
```

## Testing strategy

Initial tests should cover:

- Provider behavior with `Protocol::HTTP::Request` and `Protocol::HTTP::Response`.
- `Laiya::Configuration` and `Laiya::Configuration::Builder` behavior.
- Provider/model routing through `Laiya::Provider::Router`.
- OpenAI provider forwarding behavior, including method, path, headers, and body pass-through.
- No proxy-side JSON parsing or response wrapping for the OpenAI provider.
- Upstream HTTP error pass-through and transport exception mapping.
- HTTP API request/response compatibility for `/v1/models` and `/v1/chat/completions`.
- Streaming body pass-through behavior.
- No real OpenAI network calls in the default test suite.

Tests can use local async HTTP test servers or mocked transport boundaries.

## Implementation phases

### Phase 1: Gem skeleton

- Create gemspec and basic library structure.
- Define version and top-level namespaces.
- Add dependencies on `async`, `async-http`, and `async-service`.

### Phase 2: Configuration and routing

- Implement `Laiya::Configuration`.
- Implement `Laiya::Configuration::Builder`.
- Implement `Laiya::Provider::Router` using configured providers/model routes.
- Support a default provider and explicit model routes.

### Phase 3: OpenAI provider

- Implement `Laiya::Provider::OpenAI`.
- Implement `Protocol::HTTP::Request` -> upstream OpenAI HTTP forwarding.
- Preserve status, headers, request bodies, response bodies, and error bodies without parsing.
- Add non-streaming and streaming body pass-through.

### Phase 4: OpenAI-compatible HTTP API

- Implement `Laiya::Web::Application`.
- Implement `Laiya::Environment::Application` using `Async::HTTP::Server` directly.
- Add `bin/laiya` using `Async::Service::Configuration` and `Async::Service::Controller.run`.
- Forward `GET /v1/models`.
- Forward `POST /v1/chat/completions`.
- Map Laiya/provider transport errors to OpenAI-compatible error responses where possible.

### Later: Ruby client API

- Implement `Laiya::Client` over the provider HTTP interface.
- Add `client.models.list`.
- Add `client.chat.completions.create`.
- Add OpenAI-shaped response wrappers for normal Ruby accessors.

### Phase 5: Streaming pass-through

- Ensure provider-level streaming body pass-through.
- Ensure HTTP API streaming pass-through.
- Add OpenAI SSE parsing only for the future Ruby client API or translating providers.

### Phase 6: Additional providers and advanced routing

- Add provider/model prefix routing.
- Add fallback/load-balancing policies.
- Add translation providers that consume OpenAI-compatible HTTP and emit provider-native HTTP upstream.
- Add more providers as separate built-ins or extension gems.

## Open questions

- What should the default `Async::HTTP::Endpoint` binding be for development and production?
- Should the first Ruby convenience API prioritize OpenAI chat completions or OpenAI's newer responses API?
- Should provider implementations live in the core gem or in separate gems after OpenAI?
- Should streaming be part of the first usable release?
- How much LiteLLM-style model aliasing and fallback behavior should be included initially?
