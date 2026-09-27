# HTTP API

This guide explains how Laiya's OpenAI-compatible HTTP API handles routing, proxying, and streaming.

## Run the Async Service

Laiya runs directly on `Async::HTTP::Server` under `Async::Service`; it does not
use Rack:

```sh
bundle exec bin/laiya
```

The default service listens on `http://localhost:9292`. `LAIYA_URL` configures
the endpoint. `bin/laiya` loads optional Ruby configuration paths supplied on
the command line before starting the service.

## Endpoints

The API accepts OpenAI-compatible `Protocol::HTTP::Request` objects and returns
`Protocol::HTTP::Response` objects. Supported common routes include:

- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/responses` when the configured provider supports it
- Other OpenAI-compatible paths are forwarded to the selected provider.

Configured model routes produce a Laiya model catalog. When a provider is the
default and no model catalog is configured, `GET /v1/models` is forwarded
upstream. See [Providers and Models](../providers-and-models/) for discovery.

## Proxy and Model Routing

The built-in OpenAI provider is a direct HTTP proxy. It forwards the method,
path, headers, and request body, replacing authorization with its configured
upstream key and filtering hop-by-hop headers. It returns the upstream response
without parsing its body.

When a model route or discovery source is configured, Laiya buffers and rewinds
request bodies for known JSON completion endpoints to read the `model` field.
It forwards the original body unchanged. Streaming response bodies are not
buffered by the router.

## Streaming

OpenAI-compatible upstream SSE responses pass through unchanged. Translating
providers may adapt streaming formats. The Codex Responses endpoint passes
native Responses SSE through, including tool-call events; Laiya does not execute
client tools.
