---
title: "LLM Stack Evolution"
description: "Why the system uses oMLX and Bifrost for local inference"
type: explanation
---

# LLM Stack Evolution

The current design separates inference from routing:

- oMLX owns Apple Silicon inference, batching, model loading, and KV caching.
- Bifrost owns provider routing, API compatibility, request tracing, and
  metrics.
- OpenCode and Pi use the Bifrost endpoint rather than depending on runtime
  implementation details.

This separation keeps model-serving changes local to oMLX while preserving a
stable OpenAI-compatible client endpoint. The configured model alias is
`omlx/qwen3.8-27b`.
