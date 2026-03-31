# MegamanX (personal desktop) target configuration
# Machine-specific settings go here
{lib, ...}: {
  # Personal desktop specific configuration
  # Most config comes from roles and mkUser

  # OpenCode configuration with Ollama provider and OpenCode Go
  myConfig.opencode = {
    # Set default model - used by build, devenv, and other agents without specific models
    model = lib.mkForce "ollama/qwen3.5";

    # Configure Ollama as a provider
    providers.ollama = {
      npm = "@ai-sdk/openai-compatible";
      name = "Ollama Local";
      baseURL = "http://localhost:11434/v1";
      onePasswordItem = "";
      models = {
        "qwen3.5:2b" = {
          name = "Qwen 3.5 2B (Fast)";
        };
        "qwen3.5" = {
          name = "Qwen 3.5 9B (Balanced)";
        };
        "qwen3.5:122b" = {
          name = "Qwen 3.5 122B (Quality)";
        };
      };
    };

    # Configure OpenCode Go provider for frontier models
    providers.opencode-go = {
      name = "OpenCode Go";
      baseURL = "https://opencode.ai/zen/go/v1";
      onePasswordItem = "op://Opnix/OpenCode Go API/credential";
    };

    # Define agents - only override plan, frontier
    # build and devenv will use the global model above
    agents = {
      plan = {
        description = "Analysis and planning without making changes";
        mode = "primary";
        model = "ollama/qwen3.5:122b";
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

  # Pi (pi-coding-agent) configuration
  myConfig.pi = {
    # Example settings
    settings = {
      theme = "dark";
      editor = {
        vimMode = true;
      };
    };

    # Global AGENTS.md context
    agentsMd = ''
      # Global Agent Instructions

      This is a Nix-managed system. When working with Nix configurations:
      - Always run `devenv tasks run check:lint` before committing
      - Use the existing module patterns in modules/
      - Follow the conventional commit style
    '';

    # Example custom model pointing to local Ollama
    models.local-ollama = {
      name = "Local Ollama (Qwen 3.5)";
      provider = "openai";
      modelId = "qwen3.5";
      baseUrl = "http://localhost:11434/v1";
    };

    # Example prompt template
    prompts.review = ''
      Review this code for:
      1. Bugs and logic errors
      2. Security issues
      3. Performance problems
      4. Nix best practices (if applicable)

      Provide specific suggestions with line numbers.
    '';

    # Example skill
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
      - Check bundles.nix for role definitions
    '';
  };
}
