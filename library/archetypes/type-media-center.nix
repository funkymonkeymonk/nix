# Shared NixOS media-center profile layered on the reusable server archetype.
{...}: {
  imports = [
    ./type-server.nix
    ../../modules/nixos/media-config.nix
    ../../modules/nixos/homepage.nix
    ../../modules/services/caddy/nixos.nix
  ];

  myConfig = {
    mediaConfig.enable = true;
    homepage.enable = true;
  };
}
