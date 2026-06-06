{
  user = {
    name = "monkey";
    email = "me@willweaver.dev";
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
    model = "ollama/qwen3.5";
    enableBrowserAgents = false;
  };

  providers = {
    ollama = {
      name = "Ollama Local";
      baseURL = "http://localhost:11434/v1";
      models = {
        "qwen3.5:2b".name = "Qwen 3.5 2B (Fast)";
        "qwen3.5".name = "Qwen 3.5 9B (Balanced)";
        "qwen3.5:122b".name = "Qwen 3.5 122B (Quality)";
      };
    };
    opencode-go = {
      name = "OpenCode Go";
      baseURL = "https://opencode.ai/zen/go/v1";
      onePasswordItem = "op://Opnix/OpenCode Go API/credential";
    };
  };

  claudeCode = {};
}
