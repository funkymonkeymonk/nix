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

    # Define agents - only override plan, fast, frontier
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

      fast = {
        description = "Fast local model for quick tasks";
        mode = "primary";
        model = "ollama/qwen3.5:2b";
        prompt = "You are a fast, efficient coding assistant. Prioritize speed and quick responses.";
      };

      frontier = {
        description = "Frontier model for maximum capability";
        mode = "primary";
        model = "opencode-go/kimi-k2.5";
        prompt = "You are a frontier AI assistant with maximum capability for challenging tasks.";
      };
    };
  };
}
