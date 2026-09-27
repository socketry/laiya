# Getting Started

This guide explains how to install Laiya, configure a provider, and make an OpenAI-compatible request.

## Installation

Add Laiya to your application:

```sh
bundle add laiya
```

## Configure a Provider

Laiya's Ruby API uses a `Laiya::Configuration` to connect model IDs to
providers. For an OpenAI Platform API key:

```ruby
require "laiya"

configuration = Laiya::Configuration.build do |builder|
	builder.provider :openai, Laiya::Provider::OpenAI.new(
		api_key: ENV.fetch("OPENAI_API_KEY")
	)
	builder.model "gpt-4.1-mini", provider: :openai
	builder.default_provider :openai
end

application = Laiya::Web::Application.new(configuration: configuration)
```

The provider forwards `Protocol::HTTP::Request` and `Protocol::HTTP::Response`
objects using `Async::HTTP`. It does not parse OpenAI request or response bodies
in the direct proxy path.

For Ollama and multi-provider setups, see [Providers and Models](../providers-and-models/).

## Run the API Service

For a local OpenAI API proxy, set the API key and start Laiya:

```sh
export OPENAI_API_KEY="..."
bundle exec bin/laiya
```

The service listens on `http://localhost:9292` by default. Configure `LAIYA_URL`
to change the endpoint. See [HTTP API](../http-api/) for supported routes and
streaming behavior.
