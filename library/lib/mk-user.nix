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
  };
  claude-code = {
    enable = false;
  };
  llmClient.rtk.enable = true;
}
