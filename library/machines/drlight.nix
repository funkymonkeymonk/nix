{
  libraryLib,
  mkUser,
  inputs,
  ...
}: {
  flake.nixosConfigurations.drlight = libraryLib.mkNixosSystem {
    inherit inputs;
    hostname = "drlight";
    extraSpecialArgs = {inherit mkUser;};
    modules = [
      ../archetypes/headless-server-nixos.nix
      ../../modules/nixos/media-storage.nix
      ../../modules/nixos/media-config.nix
      ../../modules/nixos/backup.nix
      ../../modules/nixos/onepacerr.nix
      ../../modules/services/caddy/nixos.nix
      ../../modules/nixos/homepage.nix
      ../../modules/nixos/ghostty-terminfo.nix
      ../../targets/drlight
    ];
    overrides.autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#drlight";
  };
}
