---
title: "Configure the LLM Stack"
description: "Enable oMLX and Bifrost on a Darwin target"
type: how-to
---

# Configure the LLM Stack

The supported local inference stack is oMLX behind Bifrost.

## Enable oMLX

Import `modules/services/omlx/darwin.nix` and the nix-darwin Homebrew module,
then configure the target:

```nix
{
  myConfig.omlx = {
    enable = true;
    server = {
      host = "0.0.0.0";
      port = 8300;
    };
  };
}
```

The service installs the upstream oMLX formula and links the Nix-managed
`Qwen3.8-27B-4bit` model as `qwen3.8-27b`.

## Enable Bifrost

```nix
{
  myConfig.bifrost = {
    enable = true;
    upstreams.omlx = {
      url = "http://localhost:8300";
      type = "openai";
      requestTimeout = 600;
      streamIdleTimeoutInSeconds = 600;
      models = ["qwen3.8-27b"];
    };
  };
}
```

Clients should use `omlx/qwen3.8-27b` through Bifrost.

## Verify

```bash
curl http://localhost:8300/health
curl http://localhost:8300/v1/models
curl http://localhost:8081/v1/models
curl http://localhost:8081/metrics
```

Apply changes with:

```bash
devenv tasks run system:switch
```
