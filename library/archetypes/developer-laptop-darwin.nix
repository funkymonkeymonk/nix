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

  # SSH hardening (Darwin uses extraConfig, not settings.)
  services.openssh = {
    enable = true;
    extraConfig = ''
      PermitRootLogin prohibit-password
      PasswordAuthentication no
      AllowAgentForwarding yes
    '';
  };

  time.timeZone = "America/New_York";
}
