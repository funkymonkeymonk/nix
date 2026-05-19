{
  inputs,
  lib,
  ...
}: {
  myConfig = {
    skills = {
      superpowersPath = inputs.superpowers or null;
      externalInputs = lib.mkIf (inputs ? vercel-skills) {
        inherit (inputs) vercel-skills;
      };
    };

    onepassword.enable = lib.mkForce false;
    autoUpgrade.flakeUrl = lib.mkForce "";
  };

  networking.firewall.enable = true;

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

  system.stateVersion = "25.05";
}
