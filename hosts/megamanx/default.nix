# MegamanX (personal desktop) target configuration
# Thin host file — imports workstation archetype, adds machine-specific
# LLM stack (vllm-mlx, bifrost, vane) and pi customizations.
{mkUser, ...}: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "monkey";

  imports = [
    ../../library/archetypes/workstation-darwin.nix
  ];

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      # superpowersPath provided by workstation-darwin archetype

      obsidian.vaults = ["personal"];

      # Extra role beyond workstation archetype
      roles.entertainment.enable = true;

      # vllm-mlx serves Qwen 3.8 with native tool/reasoning parsers
      # Built from source with Metal-enabled mlx (prebuilt wheels merged in Nix).
      vllmMlx = {
        enable = true;
        server = {
          host = "0.0.0.0";
          port = 8300;
        };
        memoryBudgetGb = 90;
        contention = "preempt";
        models = {
          "qwen3.8-27b" = {
            path = "mlx-community/Qwen3.8-27B-4bit";
            type = "lm";
            estimatedMemoryGb = 16;
            preload = true;
          };
          "gemma4-e4b" = {
            path = "mlx-community/gemma-4-e4b-it-4bit";
            type = "lm";
            estimatedMemoryGb = 5;
            preload = true;
          };
        };
        enableAutoToolChoice = true;
        toolCallParser = "qwen";
        reasoningParser = "qwen3";
        # maxKvSize caps the per-sequence KV cache. It must be >= pi's maxTokens
        # for the bifrost model (131072) so a long agent session does not silently
        # rotate the system prompt and tool definitions out of the KV cache.
        # The bundled vllm-mlx patch supports system-prompt snapshots even when the
        # model uses RotatingKVCache (Gemma 4's sliding-window layers), so the full
        # prefix is reused each turn instead of re-prefilled.
        maxKvSize = 131072;
        # Must be >= pi's provider.timeoutMs (600s); queued lock admission
        # plus long 31B generations would otherwise be killed server-side.
        timeout = 600;
        logLevel = "INFO";
        # Switch to BatchedEngine for prefix caching across conversation turns.
        # This lets the engine reuse KV cache blocks for the growing prefix,
        # avoiding full prefill on every turn.
        enableContinuousBatching = true;
        enablePrefixCache = true;
        # Disable chunked prefill to avoid crash with large prompts (>19k tokens)
        # when prefix cache is enabled. See vllm-mlx issue #178.
        chunkedPrefillTokens = 0;
        # Enable Multi-Token Prediction for Qwen3.8's built-in MTP heads.
        # This can significantly increase generation throughput (tok/s).
        enableMtp = true;
      };

      vane = {
        enable = true;
        openaiBaseUrl = "http://bifrost.internal/v1";
        defaultModel = "qwen3.8-27b";
        embeddingModel = "nomic-embed-text:latest";
        ollamaUrl = "http://localhost:11434";
        # Point at the searxng service enabled below (myConfig.searxng.enable).
        # vane no longer auto-derives this from searxng.port — see
        # modules/services/vane/darwin.nix for why the coupling was severed.
        searxngUrl = "http://localhost:8080";
      };

      bifrost = {
        enable = true;
        # UI for request tracing, logs, token analytics:
        #   http://localhost:8081/
        # Prometheus metrics: http://localhost:8081/metrics
        logLevel = "debug";
        upstreams = {
          vllm-mlx-local = {
            url = "http://localhost:8300";
            type = "openai";
            # Must be >= vllm-mlx timeout (600s) so Bifrost doesn't abort
            # requests that are still prefill/working in the engine.
            requestTimeout = 600;
            # Idle timeout for streaming — must be >= longest prefill time.
            # Bifrost default is 60s, but vllm-mlx can take 150–200s to prefill
            # 22k+ tokens in BatchedEngine. Without this, Bifrost closes the
            # connection mid-prefill and returns 500.
            streamIdleTimeoutInSeconds = 600;
            # Retry transient 503s (busy engine, model-swap preemption) so a
            # single busy window doesn't fail an agent turn. Bifrost's stock
            # default is 0 retries.
            maxRetries = 3;
            models = [
              "qwen3.8-27b"
              "gemma4-e4b"
            ];
          };
        };
      };

      searxng.enable = true;

      caddy.enable = true;

      llmClient = {
        serverHost = "bifrost.internal";
        serverPort = "80";
      };

      pi = {
        npmPackages = {
          "pi-opencode-provider" = "^0.7.3";
          "pi-web-access" = "^0.10.7";
          "pi-subagents" = "^0.33.1";
        };

        settings = {
          theme = "dark";
          editor = {
            vimMode = true;
          };
          compaction = {
            enabled = true;
            reserveTokens = 24576;
            keepRecentTokens = 16000;
          };
          retry = {
            enabled = true;
            maxRetries = 5;
            baseDelayMs = 3000;
            provider = {
              timeoutMs = 600000;
              maxRetries = 0;
              maxRetryDelayMs = 60000;
            };
          };
          httpIdleTimeoutMs = 300000;
        };

        agentsMd = ''
          # Global Agent Instructions

          This is a Nix-managed system. When working with Nix configurations:
          - Always run `devenv tasks run check:lint` before committing
          - Use the existing module patterns in modules/
          - Follow the conventional commit style
        '';

        # Route through Bifrost to vllm-mlx for Gemma 4 with working tool calls
        models.bifrost = {
          name = "Bifrost AI Gateway";
          provider = "openai";
          modelId = "vllm-mlx-local/qwen3.8-27b";
          baseUrl = "http://bifrost.internal/v1";
          reasoning = false;
          maxTokens = 131072;
          compat = {
            supportsDeveloperRole = false;
            supportsReasoningEffort = false;
          };
        };

        models.opencode-go = {
          name = "OpenCode Go";
          provider = "opencode-go";
          modelId = "";
          onePasswordItem = "op://Opnix/OpenCode Go API/credential";
        };

        prompts.review = ''
          Review this code for:
          1. Bugs and logic errors
          2. Security issues
          3. Performance problems
          4. Nix best practices (if applicable)

          Provide specific suggestions with line numbers.
        '';
      };
    };
}
