{
  # Shared home-manager configuration
  # This module contains common home-manager settings used across all systems

  imports = [
    ./opencode.nix
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
  };
}
