---
title: "Configure the LLM Stack"
description: "Enable vllm-mlx, Bifrost, Caddy, and Vane on a Darwin target"
type: how-to
---

# Configure the LLM Stack

This guide shows how to enable the complete LLM stack on a Darwin (macOS) target.

## Prerequisites

- A Darwin target configuration (e.g., `targets/MegamanX/default.nix`)
- Apple Silicon Mac (M1/M2/M3/M4) with sufficient RAM for model loading
- ~30GB free disk space for model downloads

## Enable the Stack

Add the following to your target's `myConfig`:

```nix
{
  myConfig = {
    # Layer 3: Inference server
    vllmMlx = {
      enable = true;
      server = {
        host = "0.0.0.0";   # Bind to all interfaces
        port = 8300;         # vllm-mlx API port
      };
      memoryBudgetGb = 32;   # GPU memory budget
      contention = "preempt"; # Preempt lower-priority requests
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

    # Layer 4: AI Gateway
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

    # Layer 5: AI Search Engine
    vane = {
      enable = true;
      openaiBaseUrl = "http://bifrost.internal/v1";
      defaultModel = "qwen3.6-35b";
      embeddingModel = "mlx-community/nomicai-modernbert-embed-base-4bit";
    };

    # Layer 2: Reverse Proxy
    caddy = { enable = true; };

    # Layer 0: Search engine
    searxng = { enable = true; };
  };
}
```

## Configure Applications

### Pi Coding Agent

Add Bifrost as a model provider:

```nix
myConfig.pi = {
  enable = true;
  models.bifrost = {
    name = "Bifrost AI Gateway";
    provider = "openai";
    modelId = "vllm-mlx-local/qwen3.6-35b";
    baseUrl = "http://bifrost.internal/v1";
  };
};
```

### OpenCode

Configure OpenCode to use Bifrost:

```nix
myConfig.opencode = {
  enable = true;
  providers.bifrost = {
    npm = "@ai-sdk/openai-compatible";
    name = "Bifrost Gateway";
    baseURL = "http://bifrost.internal/v1";
    models = {
      "qwen3.6-35b" = {
        name = "Qwen3.6 35B A3B (Local MLX)";
      };
    };
  };
};
```

## Apply Configuration

```bash
# Build and switch
sudo ./result/sw/bin/darwin-rebuild switch --flake .#MegamanX --impure

# Or use the devenv task
devenv tasks run system:switch
```

## Verify the Stack

After switching, verify each layer:

```bash
# Layer 1: DNS
dig +short bifrost.internal @127.0.0.1 -p 5353

# Layer 2: Caddy
curl -s http://bifrost.internal/v1/models

# Layer 3: vllm-mlx
curl -s http://localhost:8300/v1/models

# Layer 4: Bifrost
curl -s http://localhost:8081/v1/models

# Layer 5: Vane
curl -s http://localhost:3000/
```

## Restart the Stack

If services fail to start or you change configuration:

```bash
sudo ./scripts/restart-stack.sh
```

This script performs a clean bottom-up restart, ensuring ports are freed between cycles.

## Add a New Model

1. Find an MLX-converted model on [HuggingFace mlx-community](https://huggingface.co/mlx-community)
2. Add it to your target's `vllmMlx.models`:

```nix
models = {
  "my-model" = {
    path = "mlx-community/My-Model-4bit";
    type = "lm";
    estimatedMemoryGb = 15;
  };
};
```

3. Add the model alias to Bifrost's upstream:

```nix
upstreams.vllm-mlx-local.models = [ "qwen3.6-35b" "my-model" ];
```

4. Switch to apply:

```bash
devenv tasks run system:switch
```

The model will be downloaded on first use.

## Troubleshooting

### Port Already in Use

If you see "address already in use", an old process is holding the port:

```bash
# Find and kill the process
lsof -ti:8300 | xargs kill -9

# Or use the restart script
sudo ./scripts/restart-stack.sh
```

### Model Download Fails

Check the vllm-mlx log for HuggingFace errors:

```bash
tail -f /tmp/vllm-mlx.log
```

Ensure you have sufficient disk space and network connectivity.

### Service Won't Start

Check the error log:

```bash
cat /tmp/vllm-mlx.err      # vllm-mlx errors
cat /tmp/bifrost.error.log # Bifrost errors
cat /tmp/caddy.error.log   # Caddy errors
```

### Bifrost Can't Reach vllm-mlx

Verify Caddy is routing correctly:

```bash
curl -v http://vllm-mlx.internal/v1/models
```

If this fails, check Caddy's log:

```bash
cat /tmp/caddy.error.log
```

## See Also

- [LLM Stack Reference](../reference/llm-stack.md) - Full architecture and operations
- [Add a New Machine](add-machine.md) - Configure a new Darwin target
