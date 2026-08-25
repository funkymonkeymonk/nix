# zero — Gaming/desktop NixOS machine
#
# Flake-parts module (pilot): composed from the desktop-nixos archetype +
# machine-specific modules, identical to the inline definition this
# replaced in flake.nix. Consumes the shared `libraryLib` and `mkUser`
# module args provided by ../flake-module.nix.
{
  libraryLib,
  mkUser,
  inputs,
  ...
}: {
  flake.nixosConfigurations.zero = libraryLib.mkNixosSystem {
    inherit inputs;
    hostname = "zero";
    extraSpecialArgs = {inherit mkUser;};
    modules = [
      ../archetypes/desktop-nixos.nix
      ../../modules/nixos/base.nix
      ../../modules/nixos/desktop.nix
      ../../modules/nixos/gaming.nix
      ../../modules/nixos/streaming.nix
      ../../os/nixos.nix
      inputs.disko.nixosModules.disko
      ../../disk-configs/zero.nix
      ../../machine-types/desktop.nix
      ../../modules/nixos/ghostty-terminfo.nix
      ../../targets/zero
    ];
    overrides = {
      autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#zero";
    };
  };
}
