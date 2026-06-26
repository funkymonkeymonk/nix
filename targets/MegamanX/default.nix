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
      vllmMlx = {
        enable = true;
        server = {
          host = "0.0.0.0";
          port = 8300;
        };
        memoryBudgetGb = 90;
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

      vane = {
        enable = true;
        openaiBaseUrl = "http://bifrost.internal/v1";
        defaultModel = "qwen3.6-35b";
        embeddingModel = "mlx-community/nomicai-modernbert-embed-base-4bit";
      };
      bifrost = {
        enable = true;
        logLevel = "debug";
        upstreams.vllm-mlx-local = {
          url = "http://localhost:8300";
          type = "openai";
          requestTimeout = 120;
          models = [
            "qwen3.6-35b"
          ];
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
          modelId = "vllm-mlx-local/qwen3.6-35b";
          baseUrl = "http://bifrost.internal/v1";
        };
        models.local-vllm-mlx = {
          name = "Qwen3.6 35B A3B (Bifrost)";
          provider = "openai";
          modelId = "vllm-mlx-local/qwen3.6-35b";
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
