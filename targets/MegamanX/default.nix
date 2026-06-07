# MegamanX (personal desktop) target configuration
{
  lib,
  pkgs,
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

        opencode.enable = true;
        pi.enable = true;
        homebrew.enable = true;
      };
      higgs = {
        enable = true;
        server = {
          host = "0.0.0.0";
          port = 8000;
        };
        local = {
          mlxProfile = "auto";
          raiseWiredLimit = false;
        };
        models = [
          {
            path = "mlx-community/GLM-4.7-Flash-4bit";
            name = "glm47-flash-4bit";
            package = pkgs.glm47-flash-4bit;
          }
          {
            path = "mlx-community/GLM-4.7-Flash-6bit";
            name = "glm47-flash-6bit";
            mlxProfile = "balanced";
            package = pkgs.glm47-flash-6bit;
          }
          {
            path = "mlx-community/GLM-4.7-Flash-8bit";
            name = "glm47-flash-8bit";
            mlxProfile = "throughput";
            package = pkgs.glm47-flash-8bit;
          }
          {
            path = "mlx-community/Qwen3-Embedding-4B-4bit-DWQ";
            name = "qwen-embed";
            mlxProfile = "latency";
            package = pkgs.qwen-embed;
          }
        ];
        providers = {
          opencode-go = {
            url = "https://opencode.ai/zen/go/v1";
            format = "openai";
            apiKeyOpnixItem = "op://Opnix/OpenCode Go API/credential";
          };
        };
        routes = [
          # Frontier models proxied through Higgs → OpenCode Go
          {
            pattern = "kimi-.*";
            provider = "opencode-go";
          }
          {
            pattern = "gpt-.*";
            provider = "opencode-go";
          }
          {
            pattern = "claude-.*";
            provider = "opencode-go";
          }
          {
            pattern = "gemini-.*";
            provider = "opencode-go";
          }
          {
            pattern = "opencode-go/.*";
            provider = "opencode-go";
          }
        ];
        default.provider = "higgs";
      };
      vane = {
        enable = true;
        # Higgs is the unified gateway — Vane runs natively now, so use localhost
        # Embeddings are generated natively by Higgs from loaded MLX models
        openaiBaseUrl = "http://localhost:8000/v1";
        # Models are served by Higgs at the OpenAI endpoint, discovered at runtime
        defaultModel = null;
        embeddingModel = null;
      };
      searxng.enable = true;
      opencode = {
        enable = true;
        # Default model - glm47-flash-4bit for fast coding/chat
        model = lib.mkForce "higgs/glm47-flash-4bit";

        # Configure Higgs as the unified provider
        providers.higgs = {
          npm = "@ai-sdk/openai-compatible";
          name = "Higgs Gateway";
          baseURL = "http://localhost:8000/v1";
          onePasswordItem = "";
          models = {
            "glm47-flash-4bit" = {
              name = "GLM-4.7-Flash 4bit (Fast)";
            };
            "glm47-flash-6bit" = {
              name = "GLM-4.7-Flash 6bit (Balanced)";
            };
            "glm47-flash-8bit" = {
              name = "GLM-4.7-Flash 8bit (Quality)";
            };
            "qwen-embed" = {
              name = "Qwen3 Embedding 4B (Local MLX)";
            };
          };
        };

        # Configure OpenCode Go provider for frontier models
        providers.opencode-go = {
          name = "OpenCode Go";
          baseURL = "https://opencode.ai/zen/go/v1";
          onePasswordItem = "op://Opnix/OpenCode Go API/credential";
        };

        # Define agents
        agents = {
          plan = {
            description = "Analysis and planning without making changes";
            mode = "primary";
            model = "higgs/glm47-flash-8bit";
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

        models.local-higgs = {
          name = "Higgs Gateway (GLM-4.7-Flash)";
          provider = "openai";
          modelId = "glm47-flash-4bit";
          baseUrl = "http://localhost:8000/v1";
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
