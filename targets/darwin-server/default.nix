# darwin-server target configuration
# Headless Darwin (macOS) server for macOS VM management via Lume
# Hardware: Mac M4 with 24GB RAM
# Primary User: monkey (admin)
{pkgs, ...}: {
  # Server-specific configuration
  # Most config comes from roles and mkUser in flake.nix

  # Enable SSH server for remote access
  services.openssh.enable = true;

  # Add MegamanX SSH key for passwordless login
  users.users.monkey.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

  # Install Ghostty for terminal compatibility
  environment.systemPackages = [pkgs.ghostty];

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
