# Minimal headless Darwin server profile for local inference services.
{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./base-darwin.nix
    inputs.nix-homebrew.darwinModules.nix-homebrew
    ../../modules/nixos/ghostty-terminfo.nix
    ../../modules/services/node-exporter/darwin.nix
  ];

  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;
    pi.pluginsSource = lib.mkDefault (inputs.pi-plugins.outPath or null);
  };

  services.openssh = {
    enable = true;
    extraConfig = ''
      PermitRootLogin no
      PubkeyAuthentication yes
      PasswordAuthentication no
      AllowAgentForwarding yes
    '';
  };

  users.users.root.openssh.authorizedKeys.keys = [];

  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=0
    monkey ALL=(ALL) NOPASSWD: ALL
  '';

  environment.systemPackages = with pkgs; [
    curl
    jq
  ];
}
