{inputs, ...}: {
  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;

    roles = {
      homebrew.enable = true;
      desktop.enable = true;
      entertainment.enable = true;
    };
  };

  nixpkgs.config.allowUnfree = true;

  users.users.root.openssh.authorizedKeys.keys = [];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      AllowAgentForwarding = true;
    };
  };

  time.timeZone = "America/New_York";
}
