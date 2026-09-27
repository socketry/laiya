# Ollama Integration Test

This scenario runs a local Ollama server in Docker Compose, pulls a small CPU
model, and exercises model discovery and a Chat Completions request through
`Laiya::Provider::OpenAI`.

Run it with:

```sh
bundle exec bake test:integration name=ollama
```

The model defaults to `qwen2.5:0.5b`. Override it with `OLLAMA_MODEL`. Model
files are kept in `/tmp/laiya-integration-ollama` between runs; set
`OLLAMA_MODELS_DIR` to use a different host directory. Docker Compose and a
working Docker daemon are required.
