---
title: "LLM Stack Reference"
description: "Architecture and operations for the local LLM inference stack: vllm-mlx → Bifrost → Caddy → Applications"
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
│  Layer 3: Inference (vllm-mlx)                      │
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
| `vllm-mlx.internal` | `localhost:8300` |
| `bifrost.internal` | `localhost:8081` |
| `vane.internal` | `localhost:3000` |
| `searxng.internal` | `localhost:8080` |

### Layer 3: Inference Server (vllm-mlx)

| Property | Value |
|----------|-------|
| Service | `org.vllm-mlx.server` |
| Port | 8300 |
| API | OpenAI-compatible |
| Binary | `~/.local/bin/vllm-mlx` (uv tool) or nix-packaged |
| Config | `modules/services/vllm-mlx/darwin.nix` |

vllm-mlx runs as a **user daemon**. By default it uses the nix-packaged binary, but this lacks Metal GPU support because nixpkgs disables `MLX_BUILD_METAL` in the build. For Gemma 4 models (and other large models), you should use a uv-installed binary with Metal support.

**Binary selection:**

| Mode | Binary | Metal | Notes |
|------|--------|-------|-------|
| Default (nix) | `${pkgs.vllm-mlx}/bin/vllm-mlx` | ❌ No | Works for small models on CPU |
| UV override | `~/.local/share/uv/tools/vllm-mlx/bin/vllm-mlx` | ✅ Yes | Required for Gemma 4 |

Set via `myConfig.vllmMlx.package`:

```nix
myConfig.vllmMlx = {
  enable = true;
  # Use uv-installed binary for Metal GPU support
  package = "/Users/monkey/.local/share/uv/tools/vllm-mlx/bin/vllm-mlx";
  # ...
};
```

**Patching:** The PyPI vllm-mlx wheel lacks three patches needed for Gemma 4 cross-thread MLX stream handling. Run `scripts/patch-uv-vllm-mlx.sh` after any `uv tool upgrade vllm-mlx`.

vllm-mlx supports:

- Multi-model registry (lazy loading on first use)
- Tool calling (with configurable parser: `qwen`, `gemma4`, etc.)
- Continuous batching
- Prefix caching
- Paged attention

### Layer 4: AI Gateway (Bifrost)

| Property | Value |
|----------|-------|
| Service | `com.bifrost.service` |
| Port | 8081 |
| API | OpenAI-compatible |
| Upstream | `http://vllm-mlx.internal` (via Caddy) |
| Type | `openai` |
| Config | `modules/services/bifrost/darwin.nix` |

Bifrost runs as a **user daemon**. It provides a unified OpenAI-compatible API
that routes to upstream inference servers. All LLM-consuming applications
connect to Bifrost rather than directly to vllm-mlx.

### Layer 5: Applications

| Application | Bifrost URL | Model |
|-------------|-------------|-------|
| **Vane** | `bifrost.internal/v1` | Configured per-target |
| **OpenCode** | `bifrost.internal/v1` | via Bifrost provider |
| **Pi** | `bifrost.internal/v1` | via openai provider |

## Configuration

### Target Configuration (MegamanX)

```nix
myConfig = {
  vllmMlx = {
    enable = true;
    server = {
      host = "0.0.0.0";
      port = 8300;
    };
    memoryBudgetGb = 32;
    contention = "preempt";
    models = {
      "qwen3.6-35b" = {
        path = "mlx-community/Qwen3.6-35B-A3B-4bit";
        type = "lm";
        estimatedMemoryGb = 21;
      };
    };
    enableAutoToolChoice = true;
    toolCallParser = "qwen";
    timeout = 120;
    logLevel = "INFO";
  };

  bifrost = {
    enable = true;
    logLevel = "debug";
    upstreams.vllm-mlx-local = {
      url = "http://localhost:8300";
      type = "openai";
      requestTimeout = 120;
      models = [ "qwen3.6-35b" ];
    };
  };

  vane = {
    enable = true;
    openaiBaseUrl = "http://bifrost.internal/v1";
    defaultModel = "qwen3.6-35b";
    embeddingModel = "mlx-community/nomicai-modernbert-embed-base-4bit";
  };

  caddy = { enable = true; };
  searxng = { enable = true; };
};
```

## Available Models

All models are served through vllm-mlx and exposed via Bifrost:

| Model ID | Type | Source |
|----------|------|--------|
| `mlx-community/Qwen3.6-35B-A3B-4bit` | Chat | HuggingFace (runtime) |
| `mlx-community/nomicai-modernbert-embed-base-4bit` | Embedding | HuggingFace (runtime) |

All models should be sourced from [mlx-community collections](https://huggingface.co/mlx-community/collections). When adding new models, prefer MLX-converted models from the `mlx-community` org.

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
launchctl kickstart -k gui/$(id -u)/org.vllm-mlx.server

# Full unload/reload (for config changes)
launchctl bootout gui/$(id -u)/org.vllm-mlx.server
launchctl bootstrap gui/$(id -u) /Library/LaunchDaemons/org.vllm-mlx.server.plist

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
| 8300 | vllm-mlx | HTTP (OpenAI API) |
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
cat /tmp/vllm-mlx.err     # vllm-mlx errors
cat /tmp/bifrost.error.log  # Bifrost errors
cat /tmp/caddy.error.log    # Caddy errors
```

### Model Not Loading

vllm-mlx downloads models from HuggingFace on first use. Check download progress:

```bash
cat /tmp/vllm-mlx.log | grep -i "loading\|download\|error"
```
