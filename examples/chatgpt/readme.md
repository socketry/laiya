# Laiya with ChatGPT Codex

This example uses `Laiya::Provider::Codex` to adapt Laiya's OpenAI Chat
Completions API to OpenAI's Codex Responses backend. It loads the ChatGPT login
from the Codex CLI's file-based credentials, refreshes credentials as needed,
and converts Responses events—including function calls—back to Chat Completions.
Tools are returned to the API caller; Laiya does not execute them.

This is an experimental, single-account integration with the Codex-specific
backend, not the public OpenAI Platform API. Backend behavior and supported
models may change. OpenAI documents ChatGPT authentication for local Codex
workflows and trusted private automation; do not run this as a public or
multi-user service.

## Prepare credentials

The Codex provider reads `CODEX_HOME/auth.json` (default `~/.codex/auth.json`).
It requires ChatGPT login credentials with access and refresh tokens. If the
Codex CLI currently stores credentials in the OS keyring, configure file-based
storage in `~/.codex/config.toml`:

```toml
cli_auth_credentials_store = "file"
```

Then run `codex login` and verify `codex login status`. Laiya never prints or
logs the credential values. Treat `auth.json` as a password; on a remote host,
transfer it only through a secret manager or another trusted secure channel and
restrict its permissions to the service account.

## Run locally

Create a client key and start the service from the Laiya repository root:

```sh
export LAIYA_API_KEY="$(openssl rand -hex 32)"
export CODEX_CLIENT_VERSION="$(codex --version | cut -d ' ' -f2)"
bundle install
bundle exec ruby examples/chatgpt/service.rb
```

By default it binds only to `127.0.0.1:9293`. Keep it local unless you put it
behind TLS and an access-controlled gateway. The service requires the caller to
send the `LAIYA_API_KEY` as a Bearer token; this is separate from the Codex
credentials used upstream.

The Codex provider discovers account-visible, API-supported models from the
authenticated Codex model catalog and refreshes the discovered list periodically.
`CODEX_CLIENT_VERSION` must match the installed Codex CLI version because the
catalog is filtered by client version. Set `CODEX_HOME` if the credential file
is in a non-default directory. `LAIYA_URL` can change the bind endpoint; do not
bind publicly without TLS and network access controls.

## Try it

```sh
curl http://127.0.0.1:9293/v1/chat/completions \
  -H "authorization: Bearer $LAIYA_API_KEY" \
  -H 'content-type: application/json' \
  -d '{"model":"gpt-6-luna","messages":[{"role":"user","content":"Say hello"}]}'
```

For the native Responses endpoint, send `input` as message items (this is also
the format used when preserving tool-call history):

```sh
curl -sS http://127.0.0.1:9293/v1/responses \
  -H "authorization: Bearer $LAIYA_API_KEY" \
  -H 'content-type: application/json' \
  -d '{"model":"gpt-6-luna","input":[{"role":"user","content":[{"type":"input_text","text":"Reply with exactly: Laiya connected"}]}]}'
```

Use `/v1/responses` for Codex tool calling. Laiya preserves the Responses API
tool-call items and streaming events, so the client executes the tools and
sends `function_call_output` items in the next request. The text-only
`/v1/chat/completions` adapter rejects tool-enabled requests because converting
away Codex's encrypted reasoning state would break some tool continuations.
Send full Responses input history on each request; `previous_response_id` is not
available because the Codex backend is used statelessly.

## Connect OpenCode from another computer

Put the service behind TLS and an access-controlled network gateway, then add a
custom Responses-compatible provider to OpenCode. Codex tool turns require
`/v1/responses`; the Chat Completions adapter intentionally rejects them. Keep
the Laiya API key in the client machine's secret configuration rather than
committing it:

```jsonc
{
	"$schema": "https://opencode.ai/config.json",
	"providers": {
		"laiya-codex": {
			"name": "Laiya Codex",
			"env": ["LAIYA_API_KEY"],
			"package": "@opencode/ai/providers/openai-compatible/responses",
			"settings": {
				"baseURL": "https://laiya.example.com/v1",
			},
			"models": {
				"gpt-6-luna": {"name": "GPT-6 Luna"},
			},
		},
	},
	"model": "laiya-codex/gpt-6-luna",
}
```

The custom model list in OpenCode is configured explicitly. The model can return
tool calls, which OpenCode executes on the client computer and reports back on
subsequent requests; Laiya never executes client tools.
