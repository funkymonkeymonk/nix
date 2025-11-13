{
  _config,
  pkgs,
  _lib,
  ...
}:
# NixOS module for the `drlight` machine.
# - Sets up the `monkey` user with zsh as the login shell
# - Installs zsh system-wide
# - Configures basic networking / SSH settings used in flake.nix
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Ensure the user exists with the desired shell and groups
  users.users.monkey = {
    isNormalUser = true;
    description = "monkey";
    extraGroups = ["networkmanager" "wheel"];
    # Use the zsh from nixpkgs as the login shell
    shell = pkgs.zsh;
    # Keep explicit home to match other entries; adjust if you prefer default
    home = "/home/monkey";
  };

  # Make sure zsh is available system-wide (so the shell path exists)
  environment.systemPackages = with pkgs; [
    zsh
  ];

  # Host/network/time/SSH settings for drlight
  networking = {
    hostName = "drlight";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [9000];
  };
  time.timeZone = "America/New_York";

  services.openssh.enable = true;
}
