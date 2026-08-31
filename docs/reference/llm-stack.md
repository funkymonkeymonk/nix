---
title: "LLM Stack Reference"
description: "Architecture and operations for the local oMLX and Bifrost inference stack"
type: reference
---

# LLM Stack Reference

## Architecture

Applications connect to Bifrost, which routes model requests to oMLX.

| Layer | Service | Endpoint |
|---|---|---|
| Inference | oMLX | `http://localhost:8300` |
| Gateway | Bifrost | `http://localhost:8081` |
| Applications | OpenCode and Pi | `http://bifrost.internal/v1` |

oMLX is installed from the upstream Homebrew formula through nix-darwin. The
Qwen model itself is fetched and exposed by Nix at the stable alias
`qwen3.8-27b`. Bifrost exposes that model as `omlx/qwen3.8-27b`.

## oMLX

The Darwin service is declared in `modules/services/omlx/darwin.nix` and runs
as the `org.omlx.server` user agent on port `8300`. It enables continuous
batching, hot KV caching, and SSD-backed cache storage.

Useful checks:

```bash
curl http://localhost:8300/health
curl http://localhost:8300/v1/models
launchctl print gui/$(id -u)/org.omlx.server
```

Logs are stored in `~/Library/Logs/omlx/` and `~/.omlx/logs/`.

## Bifrost

Bifrost runs on port `8081`. Its MegamanX and wweaver configurations define an
`omlx` OpenAI-compatible upstream at `http://localhost:8300`.

```bash
curl http://localhost:8081/v1/models
curl http://localhost:8081/metrics
```

Use `omlx/qwen3.8-27b` as the model ID through Bifrost. The gateway's
`streamIdleTimeoutInSeconds` is set to 600 seconds to accommodate long prompt
prefills.

## Prometheus

Prometheus scrapes Bifrost, oMLX, node-exporter, and itself. The oMLX target is
generated from the configured oMLX port rather than hard-coded in the service.

## Troubleshooting

If oMLX is not running, inspect the launchd state and logs:

```bash
launchctl print gui/$(id -u)/org.omlx.server
cat ~/Library/Logs/omlx/server.error.log
cat ~/.omlx/logs/server.log
```

If a model is not listed, verify the Nix-managed model link:

```bash
readlink ~/.omlx/models/qwen3.8-27b
```

If Metal custom kernels are needed, install the Apple Metal Toolchain through
Xcode before enabling the optional Homebrew custom-kernel build.
