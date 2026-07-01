# MegamanX (personal desktop) target configuration
{
  mkUser,
  inputs,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "monkey";

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      skills.superpowersPath = inputs.superpowers;
      roles = {
        developer.enable = true;
        desktop.enable = true;
        workstation.enable = true;
        entertainment.enable = true;
        pi.enable = true;
        homebrew.enable = true;
      };
      # vllm-mlx disabled — use Ollama instead. Config preserved for easy re-enable.
      vllmMlx = {
        enable = false;
        server = {
          host = "0.0.0.0";
          port = 8300;
        };
        memoryBudgetGb = 90;
        contention = "preempt";
        models = {
          "qwen3.6-27b" = {
            path = "mlx-community/Qwen3.6-27B-4bit";
            type = "lm";
            estimatedMemoryGb = 16;
          };
        };
        enableAutoToolChoice = true;
        toolCallParser = "qwen";
        timeout = 120;
        logLevel = "INFO";
      };

      ollama = {
        enable = true;
        host = "127.0.0.1";
        port = 11434;
      };

      vane = {
        enable = true;
        openaiBaseUrl = "http://bifrost.internal/v1";
        defaultModel = "qwen3.6:27b";
        embeddingModel = "nomic-embed-text:latest";
        ollamaUrl = "http://localhost:11434";
      };
      bifrost = {
        enable = true;
        logLevel = "debug";
        upstreams = {
          # vllm-mlx disabled — preserved for easy re-enable
          vllm-mlx-local = {
            url = "http://localhost:8300";
            type = "openai";
            requestTimeout = 120;
            models = [
              "qwen3.6-27b"
            ];
          };
          ollama-local = {
            url = "http://localhost:11434";
            type = "openai";
            requestTimeout = 600;
            models = [];
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
        };

        settings = {
          theme = "dark";
          editor = {
            vimMode = true;
          };
          compaction = {
            enabled = true;
            # Trigger compaction earlier so each summarization is smaller
            reserveTokens = 24576;
            keepRecentTokens = 16000;
          };
          retry = {
            enabled = true;
            # More retries and longer timeout for large summarizations
            maxRetries = 5;
            baseDelayMs = 3000;
            provider = {
              # Summarizing large contexts can take minutes; SDK default is too aggressive
              timeoutMs = 600000; # 10 min
              maxRetries = 0;
              maxRetryDelayMs = 60000;
            };
          };
          httpIdleTimeoutMs = 300000; # 5 minutes - needed for slow first-token latency with local models
        };

        agentsMd = ''
          # Global Agent Instructions

          This is a Nix-managed system. When working with Nix configurations:
          - Always run `devenv tasks run check:lint` before committing
          - Use the existing module patterns in modules/
          - Follow the conventional commit style
        '';

        models.bifrost = {
          name = "Bifrost AI Gateway";
          provider = "openai";
          modelId = "ollama-local/qwen3.6:27b";
          baseUrl = "http://bifrost.internal/v1";
        };
        models.local-ollama = {
          name = "Local LLM (Ollama via Bifrost)";
          provider = "openai";
          modelId = "ollama-local/qwen3.6:27b";
          baseUrl = "http://bifrost.internal/v1";
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
