{
  options,
  lib,
  ...
}: {
  # Shared home-manager configuration
  # Only applied when home-manager is available (imported in flake.nix per-host)
  # The core/bootstrap configurations don't import home-manager, so this guard
  # prevents errors on those systems.
  config = lib.mkIf (builtins.hasAttr "home-manager" options) {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };
  };
}
