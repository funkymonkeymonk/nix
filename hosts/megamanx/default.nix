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
      obsidian.vaults = ["personal"];

      # Default vllm-mlx instance: Qwen 3.8 with external MTP draft model.
      # Runs in single-model mode because --mllm-draft-model is incompatible
      # with --models-config.
      vllmMlx = {
        enable = true;
        server = {
          host = "0.0.0.0";
          port = 8300;
        };
        memoryBudgetGb = 64;
        contention = "preempt";
        models = {
          "qwen3.8-27b" = {
            path = "mlx-community/Qwen3.8-27B-8bit";
            type = "lm";
            estimatedMemoryGb = 28;
            preload = true;
          };
        };
        enableAutoToolChoice = true;
        toolCallParser = "qwen";
        reasoningParser = "qwen3";
        maxKvSize = 131072;
        timeout = 600;
        logLevel = "INFO";
        enableMetrics = true;
        # Use the external Qwen3.8-27B-MTP-8bit mlx-vlm draft model for
        # speculative decoding. This is not a standalone model; it must be
        # paired with a compatible Qwen3.8 27B target checkpoint.
        mllmDraftModel = "mlx-community/Qwen3.8-27B-MTP-8bit";
        mllmDraftKind = "mtp";
        mllmDraftBlockSize = 3;
      };

      # Second vllm-mlx instance: Gemma 4 e4b with BatchedEngine for concurrent
      # requests. Runs on a separate port so both models are available on demand
      # without reloading.
      vllmMlxInstances.gemma = {
        enable = true;
        server = {
          host = "0.0.0.0";
          port = 8301;
        };
        memoryBudgetGb = 24;
        contention = "preempt";
        models = {
          "gemma4-e4b" = {
            path = "mlx-community/gemma-4-e4b-it-4bit";
            type = "lm";
            estimatedMemoryGb = 5;
            preload = true;
          };
        };
        enableAutoToolChoice = true;
        toolCallParser = "gemma4";
        reasoningParser = "gemma4";
        maxKvSize = 131072;
        timeout = 600;
        logLevel = "INFO";
        enableMetrics = true;
        # BatchedEngine + prefix cache for concurrent requests and conversation
        # turn reuse on the Gemma instance.
        enableContinuousBatching = true;
        enablePrefixCache = true;
        chunkedPrefillTokens = 0;
      };

      # Prometheus scrapes bifrost, vllm-mlx, and node-exporter metrics
      prometheus = {
        enable = true;
        retention = "7d";
      };

      # System metrics exporter for Prometheus
      nodeExporter = {
        enable = true;
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
          vllm-mlx-qwen = {
            url = "http://localhost:8300";
            type = "openai";
            requestTimeout = 600;
            streamIdleTimeoutInSeconds = 600;
            maxRetries = 3;
            models = [
              "qwen3.8-27b"
            ];
          };
          vllm-mlx-gemma = {
            url = "http://localhost:8301";
            type = "openai";
            requestTimeout = 600;
            streamIdleTimeoutInSeconds = 600;
            maxRetries = 3;
            models = [
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
          modelId = "vllm-mlx-qwen/qwen3.8-27b";
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
