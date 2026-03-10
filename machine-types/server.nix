# Generic headless server configuration
# Uses nixos-facter for automatic hardware detection
# Minimal configuration for servers
{
  pkgs,
  lib,
  ...
}: {
  # Boot
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # Enable flakes
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Networking - basic DHCP
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.enable = true;

  # No desktop environment
  services.xserver.enable = false;

  # SSH only
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Essential packages for headless server
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
  ];

  # Locale
  time.timeZone = "America/New_York";

  # System state version
  system.stateVersion = "25.05";
}
