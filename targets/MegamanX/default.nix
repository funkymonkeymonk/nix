# MegamanX (personal desktop) target configuration
{
  lib,
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
        llm-host.enable = true;
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
            path = "mlx-community/Qwen3-Coder-Next-4bit";
            name = "qwen-coder";
          }
          {
            path = "mlx-community/Qwen3.6-35B-A3B-8bit";
            name = "qwen-35b";
            mlxProfile = "throughput";
          }
          {
            path = "mlx-community/Qwen3-Embedding-4B-4bit-DWQ";
            name = "qwen-embed";
            mlxProfile = "latency";
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
        # Default model - qwen-coder handles both coding and fast chat
        model = lib.mkForce "higgs/qwen-coder";

        # Configure Higgs as the unified provider
        providers.higgs = {
          npm = "@ai-sdk/openai-compatible";
          name = "Higgs Gateway";
          baseURL = "http://localhost:8000/v1";
          onePasswordItem = "";
          models = {
            "qwen-coder" = {
              name = "Qwen3 Coder Next (Local MLX)";
            };
            "qwen-35b" = {
              name = "Qwen3.6 35B A3B (Local MLX)";
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
            model = "higgs/qwen-35b";
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
          name = "Higgs Gateway (Qwen Coder)";
          provider = "openai";
          modelId = "qwen-coder";
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
