---
title: "LLM Stack Reference"
description: "Architecture and operations for the local LLM inference stack: vMLX → Bifrost → Caddy → Applications"
type: reference
---

# LLM Stack Reference

## Architecture

The LLM stack follows a layered architecture where each layer has a single responsibility:

```
┌─────────────────────────────────────────────────────┐
│  Layer 5: Applications                              │
│  Vane · OpenCode · Pi                               │
│  All connect to Bifrost at bifrost.internal:80       │
├─────────────────────────────────────────────────────┤
│  Layer 4: AI Gateway (Bifrost)                      │
│  Proxies all AI requests to upstream inference       │
│  Unified OpenAI-compatible API on port 8081          │
├─────────────────────────────────────────────────────┤
│  Layer 3: Inference (vMLX)                          │
│  MLX inference engine on Metal GPU                  │
│  OpenAI-compatible API on port 8300                  │
├─────────────────────────────────────────────────────┤
│  Layer 2: Reverse Proxy (Caddy)                     │
│  Routes *.internal → local services                 │
│  Service discovery via hostnames                    │
├─────────────────────────────────────────────────────┤
│  Layer 1: DNS (dnsmasq)                             │
│  Resolves *.internal → 127.0.0.1                    │
│  Port 5353, configured via /etc/resolver            │
└─────────────────────────────────────────────────────┘
```

## Layers

### Layer 1: DNS Resolver (dnsmasq)

| Property | Value |
|----------|-------|
| Service | `com.dnsmasq.service` |
| Port | 5353 |
| Config | `/etc/resolver/internal` |
| Resolves | `*.internal` → `127.0.0.1` |

dnsmasq runs as a **root daemon** via launchd. It resolves all `.internal` hostnames to
`127.0.0.1` so that Caddy can route them to local services.

### Layer 2: Reverse Proxy (Caddy)

| Property | Value |
|----------|-------|
| Service | `com.caddy.service` |
| Port | 80 (HTTP only, no HTTPS) |
| Config | Generated `Caddyfile` from Nix |
| Data | `~/.local/share/caddy/` |

Caddy runs as a **root daemon** and proxies `.internal` hostnames to their respective services:

| Hostname | Upstream |
|----------|----------|
| `vmlx.internal` | `localhost:8300` |
| `bifrost.internal` | `localhost:8081` |
| `vane.internal` | `localhost:3000` |
| `searxng.internal` | `localhost:8080` |

### Layer 3: Inference Server (vMLX)

| Property | Value |
|----------|-------|
| Service | `org.vmlx.server` |
| Port | 8300 |
| API | OpenAI-compatible |
| Model | `mlx-community/gemma-4-12B-it-OptiQ-4bit` |
| Config | `modules/services/vmlx/darwin.nix` |

vMLX runs as a **user daemon**. It self-installs via `uv` if not present.
It uses Metal GPU acceleration and supports tool calling, prefix caching,
paged attention, and disk cache.

### Layer 4: AI Gateway (Bifrost)

| Property | Value |
|----------|-------|
| Service | `com.bifrost.service` |
| Port | 8081 |
| API | OpenAI-compatible |
| Upstream | `http://vmlx.internal` (via Caddy) |
| Type | `openai` |
| Config | `modules/services/bifrost/darwin.nix` |

Bifrost runs as a **user daemon**. It provides a unified OpenAI-compatible API
that routes to upstream inference servers. All LLM-consuming applications
connect to Bifrost rather than directly to vMLX.

### Layer 5: Applications

| Application | Bifrost URL | Model |
|-------------|-------------|-------|
| **Vane** | `bifrost.internal/v1` | `gemma-4-12B-it-OptiQ-4bit` |
| **OpenCode** | `vmlx.internal/v1` | via `vmlx` provider |
| **Pi** | `vmlx.internal/v1` | `openai` provider |

## Available Models

All models are served through vMLX and exposed via Bifrost:

| Model ID | Type | Source |
|----------|------|--------|
| `mlx-community/gemma-4-12B-it-OptiQ-4bit` | Chat | HuggingFace (runtime) |
| `mlx-community/gemma-4-31B-it-OptiQ-4bit` | Chat | HuggingFace (runtime) |
| `mlx-community/DeepSeek-V4-Flash-4bit` | Chat | HuggingFace (runtime) |
| `mlx-community/nomicai-modernbert-embed-base-4bit` | Embedding | HuggingFace (runtime) |

## Operations

### Restarting the Stack

Use the restart script for clean lifecycle management:

```bash
sudo ./scripts/restart-stack.sh
```

This restarts services bottom-up (DNS → Proxy → Inference → Gateway → Apps),
ensuring ports are freed between stops and starts to prevent conflicts.

### Manual Restart

For individual services:

```bash
# Kill process and let launchd restart
launchctl kickstart -k gui/$(id -u)/org.vmlx.server

# Full unload/reload (for config changes)
launchctl bootout gui/$(id -u)/org.vmlx.server
launchctl bootstrap gui/$(id -u) /Library/LaunchDaemons/org.vmlx.server.plist

# Root services (dnsmasq, Caddy)
sudo launchctl bootout system/com.dnsmasq.service
sudo launchctl bootstrap system /Library/LaunchDaemons/com.dnsmasq.service.plist
```

### Verifying the Stack

Run the integration test suite:

```bash
./tests/test-stack-integration.sh
```

This tests all layers from DNS resolution through to chat completions.

## Port Reference

| Port | Service | Protocol |
|------|---------|----------|
| 5353 | dnsmasq | DNS |
| 80 | Caddy | HTTP |
| 8300 | vMLX | HTTP (OpenAI API) |
| 8081 | Bifrost | HTTP (OpenAI API) |
| 3000 | Vane | HTTP (Next.js) |
| 8080 | SearXNG | HTTP |

## Troubleshooting

### Port Conflicts

If a service fails with "address already in use", an old process is holding the port.
Use `restart-stack.sh` which properly frees ports between stop and start cycles.

### Service Not Starting

Check the service log:

```bash
cat /tmp/vmlx.err     # vMLX errors
cat /tmp/bifrost.error.log  # Bifrost errors
cat /tmp/caddy.error.log    # Caddy errors
```

### Model Not Loading

vMLX downloads models from HuggingFace on first use. Check download progress:

```bash
cat /tmp/vmlx.log | grep -i "loading\|download\|error"
```
