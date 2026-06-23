---
title: "LLM Stack Evolution"
description: "Why we replaced Higgs + Ollama with vllm-mlx + Bifrost + Caddy"
type: explanation
---

# LLM Stack Evolution

This document explains the design decisions behind the current LLM stack architecture and why previous approaches were replaced.

## Historical Context

### Phase 1: Ollama (2024–2025)

The initial stack used **Ollama** as the local inference server:

- Simple `ollama run` UX
- Good model ecosystem (pull any model)
- Worked across macOS and Linux

**Limitations:**
- No native tool calling support
- Limited batching → poor throughput under load
- Models downloaded at runtime (not reproducible)
- No prefix caching → slow repeated prompts
- CPU fallback when GPU memory exhausted (unpredictable performance)

### Phase 2: Higgs (2025–2026)

Replaced Ollama with **Higgs**, a custom MLX-based inference server:

- Native MLX acceleration on Apple Silicon
- OpenAI-compatible API
- Model routing to frontier providers (OpenCode Go)
- TOML-based configuration

**Limitations:**
- Custom codebase requiring ongoing maintenance
- Limited model format support (only MLX-converted models)
- No continuous batching
- Single-model-at-a-time (no hotswap)
- Tight coupling between inference and routing logic

### Phase 3: vllm-mlx + Bifrost + Caddy (2026–present)

The current architecture separates concerns into distinct layers:

## Design Principles

### 1. Separation of Concerns

Each layer has exactly one responsibility:

| Layer | Responsibility | Technology |
|-------|---------------|------------|
| DNS | Hostname resolution | dnsmasq |
| Proxy | HTTP routing | Caddy |
| Inference | Model serving | vllm-mlx |
| Gateway | API unification | Bifrost |
| Apps | User interfaces | Vane, OpenCode, Pi |

This means:
- **vllm-mlx** focuses only on fast inference
- **Bifrost** focuses only on request routing
- **Caddy** focuses only on HTTP proxying
- Each can be replaced independently

### 2. Use Battle-Tested Tools

Instead of building custom solutions, we compose proven open-source tools:

- **vllm-mlx**: Built on vLLM (production inference at scale)
- **Bifrost**: Built on LiteLLM proxy (widely deployed)
- **Caddy**: Modern reverse proxy with automatic HTTPS

### 3. Reproducible Configuration

All configuration is in Nix:

- No runtime model downloads (models specified in config)
- No manual service setup (launchd plists generated)
- No ad-hoc DNS configuration (`/etc/resolver` managed)

### 4. Multi-Model Support

vllm-mlx supports multiple models in a single registry:

```yaml
models:
  - path: mlx-community/Qwen3.6-35B-A3B-4bit
    name: qwen3.6-35b
  - path: mlx-community/nomicai-modernbert-embed-base-4bit
    name: nomic-embed
    type: embedding
```

Models are lazily loaded on first request, enabling:
- Chat + embedding in one server
- Fast model switching
- Memory-efficient operation

## Why vllm-mlx Over Higgs

| Feature | Higgs | vllm-mlx |
|---------|-------|----------|
| Maintenance | Custom code | Community-maintained |
| Batching | None | Continuous |
| Prefix caching | No | Yes |
| Tool calling | Basic | Full (with parser config) |
| Multi-model | No | Yes (registry) |
| Embedding | Separate | Integrated |
| Model formats | MLX only | MLX + GGUF + more |

## Why Bifrost Over Higgs Routing

Higgs combined inference and routing in one process. Bifrost separates them:

| Aspect | Higgs | Bifrost |
|--------|-------|---------|
| Upstream providers | Hardcoded | Configurable |
| API format | OpenAI only | OpenAI, Anthropic, Gemini |
| Load balancing | None | Built-in |
| Fallback | None | Automatic |
| Metrics | Basic | Prometheus-compatible |

## Why Caddy Over Direct Connections

Previously, applications connected directly to inference servers:

```
Vane → localhost:8000  # Higgs
Pi → localhost:8000    # Higgs
```

This meant:
- Hardcoded ports in every app
- No way to change inference backend without updating all apps
- No load balancing or failover

With Caddy:

```
Vane → bifrost.internal → Caddy → Bifrost
Pi → bifrost.internal → Caddy → Bifrost
```

Benefits:
- Apps use hostnames, not ports
- Switch inference backend by updating Caddy config
- Add load balancing without touching apps
- Internal hostnames are self-documenting

## Migration Path

If you're on Higgs or Ollama:

1. Remove old service config from your target
2. Add vllm-mlx + Bifrost + Caddy config
3. Update app base URLs to use `*.internal` hostnames
4. Run `sudo ./scripts/restart-stack.sh`

See [Configure the LLM Stack](../how-to/configure-llm-stack.md) for the full setup.

## Future Directions

Potential future enhancements:

- **Remote inference**: Add upstream providers for cloud models
- **Model caching**: Pre-download models at build time
- **Metrics dashboard**: Grafana for request latency and throughput
- **Auto-scaling**: Spawn multiple vllm-mlx instances for load
