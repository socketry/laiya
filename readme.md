# Laiya

The AI layer for Ruby.

[![Development Status](https://github.com/socketry/laiya/workflows/Test/badge.svg)](https://github.com/socketry/laiya/actions?workflow=Test)

Laiya is a play on “Layer AI”: an OpenAI-compatible HTTP API and provider proxy
built on `Async::HTTP`.

## Motivation

LLM providers expose overlapping APIs but differ in authentication, model
catalogs, and protocol details. Laiya provides a shared OpenAI-compatible HTTP
surface and routes requests to configured providers, while allowing compatible
providers to proxy request and response bodies without buffering them.

## Usage

Please see the [project documentation](https://socketry.github.io/laiya/) for more details.

  - [Getting Started](https://socketry.github.io/laiya/guides/getting-started/index) - This guide explains how to install Laiya, configure a provider, and make an OpenAI-compatible request.

  - [Providers and Models](https://socketry.github.io/laiya/guides/providers-and-models/index) - This guide explains how to route model IDs to providers and when to discover a provider's model catalog.

  - [HTTP API](https://socketry.github.io/laiya/guides/http-api/index) - This guide explains how Laiya's OpenAI-compatible HTTP API handles routing, proxying, and streaming.

  - [ChatGPT Codex Provider](https://socketry.github.io/laiya/guides/chatgpt-codex/index) - This guide explains how to run the experimental Codex provider with a ChatGPT login while keeping tool execution on the client.

## Releases

Please see the [project releases](https://socketry.github.io/laiya/releases/index) for all releases.

### Unreleased

  - Add an OpenAI-compatible HTTP API with OpenAI and Ollama providers, model discovery, and model limits.
  - Add an experimental ChatGPT Codex provider and an Async::Service launcher.

## Contributing

We welcome contributions to Laiya.

### Running tests

``` sh
bundle exec bake test
```

### Running integration tests

The Ollama integration test requires Docker Compose and downloads a small CPU
model on its first run:

``` sh
bundle exec bake test:integration name=ollama
```

### Making releases

``` sh
bundle exec bake gem:github:release:patch
```

See [bake-gem-github](https://github.com/socketry/bake-gem-github) for release setup and process.

### Developer Certificate of Origin

Contributions must comply with the [Developer Certificate of Origin](https://developercertificate.org/).
