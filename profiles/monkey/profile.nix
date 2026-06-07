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

    opencode.enable = true;
    pi.enable = true;
    homebrew.enable = true;
  };

  opencode = {
    model = "higgs/glm47-flash-4bit";
    enableBrowserAgents = false;
  };

  providers = {
    opencode-go = {
      name = "OpenCode Go";
      baseURL = "https://opencode.ai/zen/go/v1";
      onePasswordItem = "op://Opnix/OpenCode Go API/credential";
    };
  };

  claudeCode = {};
}
