# MegamanX (personal desktop) target configuration
{
  lib,
  mkUser,
  pkgs,
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
        llm-host.enable = true;
        opencode.enable = true;
        pi.enable = true;
        homebrew.enable = true;
      };
      vmlx = {
        enable = true;
        server = {
          host = "0.0.0.0";
          port = 8300;
        };
        kvCacheQuantization = "q8";
        enableDiskCache = true;
        maxPromptTokens = 32768;
        model = {
          name = "gemma4-31B-OptiQ-4bit";
          path = "mlx-community/gemma-4-31B-it-OptiQ-4bit";
          package = pkgs.gemma4-31B-OptiQ-4bit;
        };
      };
      ds4.enable = false;
      vane = {
        enable = true;
        openaiBaseUrl = "http://localhost:8300/v1";
        defaultModel = "gemma4-31B-OptiQ-4bit";
        embeddingModel = null;
      };
      bifrost = {
        enable = true;
        logLevel = "debug";
        upstreams.vmlx-local = {
          url = "http://127.0.0.1:8300";
          type = "vllm";
          models = ["gemma4-31B-OptiQ-4bit"];
        };
      };
      searxng.enable = true;
      caddy.enable = true;
      opencode = {
        enable = true;
        model = lib.mkForce "vmlx/gemma4-31B-OptiQ-4bit";

        providers.vmlx = {
          npm = "@ai-sdk/openai-compatible";
          name = "vMLX (local Gemma 4 31B)";
          baseURL = "http://localhost:8300/v1";
          onePasswordItem = "";
          models = {
            "gemma4-31B-OptiQ-4bit" = {
              name = "Gemma 4 31B OptiQ";
            };
          };
        };

        providers.opencode-go = {
          name = "OpenCode Go";
          baseURL = "https://opencode.ai/zen/go/v1";
          onePasswordItem = "op://Opnix/OpenCode Go API/credential";
        };

        agents = {
          plan = {
            description = "Analysis and planning without making changes";
            mode = "primary";
            model = "vmlx/gemma4-31B-OptiQ-4bit";
            prompt = "You are a planning assistant. Analyze code and create plans without making changes.";
            permission = {
              edit = "deny";
              bash = "ask";
            };
          };

          frontier = {
            description = "Frontier model for maximum capability";
            mode = "primary";
            model = "opencode-go/kimi-k2.5";
            prompt = "You are a frontier AI assistant with maximum capability for challenging tasks.";
          };
        };
      };
      pi = {
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

        models.local-vmlx = {
          name = "Gemma 4 31B OptiQ (vMLX local)";
          provider = "openai";
          modelId = "gemma4-31B-OptiQ-4bit";
          baseUrl = "http://localhost:8300/v1";
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
          # Nix Development Skill

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
