{
  # Shared home-manager configuration
  # This module contains common home-manager settings used across all systems

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    sharedModules = [
      ./litellm.nix
    ];
  };
}
