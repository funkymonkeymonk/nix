{
  # Shared home-manager configuration
  # This module contains common home-manager settings used across all systems
  # All hosts that import ./modules must also import the appropriate
  # home-manager module (darwinModules or nixosModules) from flake.nix
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
