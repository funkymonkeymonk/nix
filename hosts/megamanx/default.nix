# MegamanX (personal desktop) target configuration
# Thin host file — imports workstation archetype, adds machine-specific
# LLM stack (vllm-mlx, bifrost, vane) and pi customizations.
{
  mkUser,
  inputs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "monkey";

  imports = [
    ../../library/archetypes/workstation-darwin.nix
  ];

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      skills.superpowersPath = inputs.superpowers;

      # Extra role beyond workstation archetype
      roles.entertainment.enable = true;

      # vllm-mlx serves Gemma 4 with native tool/reasoning parsers
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
          "gemma4-31b" = {
            path = "mlx-community/gemma-4-31b-it-4bit";
            type = "lm";
            estimatedMemoryGb = 18;
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
        toolCallParser = "gemma4";
        reasoningParser = "gemma4";
        maxKvSize = 65536;
        timeout = 120;
        logLevel = "INFO";
      };

      vane = {
        enable = true;
        openaiBaseUrl = "http://bifrost.internal/v1";
        defaultModel = "gemma4-31b";
        embeddingModel = "nomic-embed-text:latest";
        ollamaUrl = "http://localhost:11434";
      };

      bifrost = {
        enable = true;
        logLevel = "debug";
        upstreams = {
          vllm-mlx-local = {
            url = "http://localhost:8300";
            type = "openai";
            requestTimeout = 120;
            models = [
              "gemma4-31b"
              "gemma4-e4b"
            ];
          };
        };
      };

      # Ollama disabled — vllm-mlx handles all local inference
      ollama = {
        enable = false;
        host = "127.0.0.1";
        port = 11434;
        keepAlive = "0";
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
          modelId = "vllm-mlx-local/gemma4-31b";
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

        skills.nix = ''
          ---
          description: Nix development skill for working with flakes, modules, and configurations
          ---

          Use this skill when working with Nix flakes, modules, or configurations.

          ## Conventions
          - Use `mkOption` for all configurable values
          - Place modules in appropriate directories: common/, nixos/, darwin/
          - Test with `devenv tasks run check:lint` before finishing
          - Follow existing patterns in the codebase

          ## Tools
          - Read existing modules in modules/ for examples
          - Use lib.optionalAttrs for platform-specific config
          - Check modules/roles/ for role definitions
        '';
      };
    };
}
