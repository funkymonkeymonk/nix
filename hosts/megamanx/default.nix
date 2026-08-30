# MegamanX (personal desktop) target configuration
# Thin host file — imports workstation archetype, adds machine-specific
# LLM stack (oMLX, Bifrost, Vane) and pi customizations.
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

      roles.opencode.enable = true;

      # oMLX serves the Nix-provided 4-bit Qwen checkpoint through its
      # continuous-batching and tiered KV-cache engine.
      omlx = {
        enable = true;
        server = {
          host = "0.0.0.0";
          port = 8300;
        };
        logLevel = "info";
        memoryGuardGb = 96;
        maxConcurrentRequests = 8;
        hotCacheMaxSize = "20GB";
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
        # No Ollama service runs on this host (vllm-mlx + Bifrost handle all
        # local inference) — leave embeddings unconfigured rather than
        # pointing at a service that doesn't exist.
        embeddingModel = null;
        ollamaUrl = null;
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
