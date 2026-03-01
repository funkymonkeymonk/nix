# openclaw-vm target configuration
# Dedicated OpenClaw host running in a microvm
{pkgs, ...}: {
  # Override hostname
  networking.hostName = "openclaw-vm";

  # Create openclaw user
  users.users.openclaw = {
    isNormalUser = true;
    description = "OpenClaw User";
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
    home = "/home/openclaw";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8" # MegamanX
    ];
  };

  # Root SSH access
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8" # MegamanX
  ];

  # Ensure zsh is available
  programs.zsh.enable = true;

  # Allow passwordless sudo for openclaw user
  security.sudo.wheelNeedsPassword = false;

  # Time zone
  time.timeZone = "America/New_York";

  # OpenClaw specific configuration
  # The openclaw-host role provides the package and home-manager config
  networking.firewall.allowedTCPPorts = [8080]; # OpenClaw gateway port (adjust as needed)
}
