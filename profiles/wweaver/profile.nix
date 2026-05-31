{
  user = {
    name = "wweaver";
    email = "wweaver@justworks.com";
    fullName = "Will Weaver";
  };

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

  opencode = {
    model = "just-llms/claude-sonnet-4-6";
    disabledProviders = ["opencode"];
    enableBrowserAgents = false;
  };

  providers = {
    just-llms = {
      name = "Just LLMs";
      baseURL = "https://litellm.justworksai.net";
      onePasswordItem = "op://Justworks/Justworks LiteLLM/wweaver-poweruser-key";
      dynamicModels = true;
    };
    ollama = {
      name = "Ollama (local)";
      baseURL = "http://localhost:11434/v1";
      models = {
        "qwen3.5:latest".name = "Qwen 3.5 (7B)";
        "qwen3.5:2b".name = "Qwen 3.5 (2B)";
      };
    };
  };

  claudeCode = {};
}
