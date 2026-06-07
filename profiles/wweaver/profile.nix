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
      baseURLOpnixItem = "op://Justworks/LiteLLM/baseURL";
      onePasswordItem = "op://Justworks/Justworks LiteLLM/wweaver-poweruser-key";
      dynamicModels = true;
    };
  };

  claudeCode = {};
}
