# ChatGPT Codex Provider

This guide explains how to run the experimental Codex provider with a ChatGPT login while keeping tool execution on the client.

## Authentication and Trust

The Codex provider reads ChatGPT credentials from
`CODEX_HOME/auth.json` (default `~/.codex/auth.json`) and refreshes tokens when
needed. If the Codex CLI uses an OS keyring, configure file-backed credentials
and run `codex login`:

```toml
cli_auth_credentials_store = "file"
```

Treat `auth.json` as a password. This provider calls the Codex-specific backend,
not the public OpenAI Platform API. It is experimental and intended for a
trusted, single-user service. Do not expose it to the public internet or an
untrusted multi-user environment.

## Start the Example

From the Laiya repository root:

```sh
export LAIYA_API_KEY="$(openssl rand -hex 32)"
bundle exec ruby examples/chatgpt/service.rb
```

The example binds to `127.0.0.1:9293`. It requires the client to send the
separate `LAIYA_API_KEY` as a Bearer token. For remote clients, use TLS and a
private access-controlled network. See the [example files](https://github.com/socketry/laiya/tree/main/examples/chatgpt).

## Client-Owned Tool Execution

Use `POST /v1/responses` for tool calling. Laiya preserves the Codex Responses
stream and response items. The client executes a returned function call and
sends its `function_call_output` back in the next request. Since Codex is used
statelessly, send the full input history, including the previous response's
reasoning and function-call items; `previous_response_id` is not supported.

The text-only `POST /v1/chat/completions` adapter rejects tool-enabled requests
so it cannot silently lose Codex reasoning state.
