# Laiya

Laiya is an OpenAI-compatible HTTP API and provider proxy built on `Async::HTTP`.
The initial release supports multiple configured models/providers and forwards
OpenAI-compatible requests using `Protocol::HTTP::Request` and
`Protocol::HTTP::Response`.

[![Development Status](https://github.com/socketry/laiya/workflows/Test/badge.svg)](https://github.com/socketry/laiya/actions?workflow=Test)

## Configuration

``` ruby
require "laiya"

configuration = Laiya::Configuration.build do |builder|
	builder.provider :openai, Laiya::Provider::OpenAI.new(api_key: ENV.fetch("OPENAI_API_KEY"))
	builder.model "gpt-4.1-mini", provider: :openai
	builder.default_provider :openai
end

application = Laiya::Web::Application.new(configuration: configuration)
```

The router inspects the `model` field for known JSON request endpoints. It
buffers and rewinds the request body before forwarding it. The OpenAI provider
does not parse or transform request or response bodies, so streamed responses
remain streamed.

## Running the API

Set `OPENAI_API_KEY` and run:

``` sh
bundle exec bin/laiya
```

The default service listens at `http://localhost:9292`. Set `LAIYA_URL` to
change the bind endpoint.

## Development

``` sh
bundle exec bake agent:context:install
bundle exec bake test
bundle exec bake modernize
```

Tests use Sus and local fake providers; they do not require an OpenAI account or
network access.
