# dev-vm target configuration
# Development environment in a microvm
{pkgs, ...}: {
  # Override hostname
  networking.hostName = "dev-vm";

  # Create development user (matching host user pattern)
  users.users.dev = {
    isNormalUser = true;
    description = "Development User";
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
    home = "/home/dev";
    password = "dev"; # Simple password for dev VM
  };

  # Ensure zsh is available
  programs.zsh.enable = true;

  # Allow passwordless sudo for dev user
  security.sudo.wheelNeedsPassword = false;

  # Time zone
  time.timeZone = "America/New_York";
}
