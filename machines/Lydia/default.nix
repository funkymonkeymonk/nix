{
  lib,
  pkgs,
  ...
}: let
  nixBuilderPublicKey =
    builtins.replaceStrings ["\n" "\r"] ["" ""]
    (builtins.readFile ../../keys/nix-remote-builder-megamanx.pub);
  nixBuilderAuthorizedKey = "restrict,command=\"/nix/var/nix/profiles/default/bin/nix-daemon --stdio\" ${nixBuilderPublicKey}";
in {
  # Target system: aarch64-darwin
  imports = [
    ../../library/archetypes/workstation-darwin.nix
  ];

  system.stateVersion = 4;
  system.primaryUser = "monkey";
  myConfig.users = lib.mkDefault [
    {
      name = "monkey";
      fullName = "monkey";
      email = "me@willweaver.dev";
    }
  ];

  # Keep normal SSH access available for remote deployment and recovery.
  myConfig.ssh.enable = true;

  myConfig.roles."developer".enable = true;
  myConfig.roles."desktop".enable = true;
  myConfig.roles."workstation".enable = true;
  myConfig.roles."agent-skills".enable = true;
  myConfig.roles."pi".enable = true;

  nix.settings.trusted-users = ["root" "monkey" "nixbuilder"];

  # The restricted account exposes only the Nix daemon protocol to Zero.
  users.knownUsers = ["nixbuilder"];
  users.users.nixbuilder = {
    uid = 502;
    gid = 20;
    description = "Nix remote builder for Zero";
    home = "/var/empty";
    shell = pkgs.bashInteractive;
    ignoreShellProgramCheck = true;
    isHidden = true;
    createHome = false;
    openssh.authorizedKeys.keys = [nixBuilderAuthorizedKey];
  };

  services.openssh.extraConfig = ''
    Match User nixbuilder
      AuthenticationMethods publickey
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      AllowAgentForwarding no
      AllowTcpForwarding no
      PermitTTY no
      X11Forwarding no
      ForceCommand /nix/var/nix/profiles/default/bin/nix-daemon --stdio

    Match all
  '';
}
