name: email: {
  users = [
    {
      inherit name email;
      fullName = "Will Weaver";
      isAdmin = true;
      sshIncludes = [];
    }
  ];
  onepassword.enable = true;
  opencode = {
    enable = true;
    model = "local-bifrost/omlx/qwen3.8-27b";
  };
  claude-code = {
    enable = false;
  };
  llmClient.rtk.enable = true;
}
