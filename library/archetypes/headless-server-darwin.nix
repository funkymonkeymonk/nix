{inputs, ...}: {
  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;
  };

  users.users.root.openssh.authorizedKeys.keys = [];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowAgentForwarding = true;
    };
  };

  time.timeZone = "America/New_York";
}
