# Headless Darwin host for local inference services.
{
  inputs,
  lib,
  ...
}: {
  imports = [
    ./base-darwin.nix
    ./server-observability-darwin.nix
    inputs.nix-homebrew.darwinModules.nix-homebrew
    ../../modules/nixos/ghostty-terminfo.nix
    ../../modules/services/bifrost/darwin.nix
    ../../modules/services/caddy/darwin.nix
    ../../modules/services/omlx/darwin.nix
    ../../modules/services/searxng/darwin.nix
  ];

  myConfig = {
    skills.superpowersPath = inputs.superpowers or null;
    pi.pluginsSource = lib.mkDefault (inputs.pi-plugins.outPath or null);

    roles.pi.enable = true;
    zellij.enable = true;

    bifrost.enable = true;
    caddy.enable = true;
    omlx.enable = true;
    searxng.enable = true;
  };
}
