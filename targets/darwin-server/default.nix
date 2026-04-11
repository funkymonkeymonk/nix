# darwin-server target configuration
# Headless Darwin (macOS) server for macOS VM management via Lume
# Hardware: Mac M4 with 24GB RAM
# Primary User: monkey (admin)
_: {
  # Server-specific configuration
  # Most config comes from roles and mkUser in flake.nix

  # Enable SSH server for remote access
  services.openssh.enable = true;

  # Lume configuration for macOS VMs
  myConfig.lume = {
    enable = true;
    enableBackgroundService = true;
    port = 7777;
    enableAutoUpdater = true;
    # Pre-pull macOS Tahoe vanilla image
    prePullImages = ["macos-tahoe-vanilla:latest"];
  };
}
