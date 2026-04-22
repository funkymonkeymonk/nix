# Core - Absolute minimum for ALL systems
# These packages are available on every single system including
# bootstrap, servers, microvms, and personal machines
{pkgs, ...}: {
  # Absolute essentials that should be available on any Unix system
  environment.systemPackages = with pkgs; [
    # Without these, the system is barely usable
    git # Required for nix flakes
    curl # Basic networking
    wget # Alternative fetch
    coreutils # Basic Unix utilities
    vim # Emergency editor
  ];
}
