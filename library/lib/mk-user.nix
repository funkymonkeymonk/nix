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
    model = "opencode/big-pickle";
  };
  claude-code = {
    enable = false;
  };
  llmClient.rtk.enable = true;
}
