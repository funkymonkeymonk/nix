# Minimal headless Darwin server profile for local inference services.
{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./base-darwin.nix
    inputs.nix-homebrew.darwinModules.nix-homebrew
    ../../modules/nixos/ghostty-terminfo.nix
  ];

  myConfig.skills.superpowersPath = inputs.superpowers or null;

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
