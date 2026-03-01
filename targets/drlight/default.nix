{...}:
# NixOS module for the `drlight` machine.
# - Configures basic networking / SSH settings used in flake.nix
# - Runs Jellyfin and Mealie services
# Note: User configuration comes from modules/nixos/base.nix via myConfig.users
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/services.nix
  ];

  # Host/network/time settings for drlight
  networking = {
    hostName = "drlight";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [9000];
  };
  time.timeZone = "America/New_York";
}
