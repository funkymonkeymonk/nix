{inputs, ...}: {
  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;
  };

  users.users.root.openssh.authorizedKeys.keys = [];

  services.openssh = {
    enable = true;
    extraConfig = ''
      PermitRootLogin no
      PasswordAuthentication no
      AllowAgentForwarding yes
    '';
  };

  time.timeZone = "America/New_York";
}
