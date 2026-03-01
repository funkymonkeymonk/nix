{
  inputs,
  pkgs,
  ...
}:
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

  services.openssh.enable = true;

  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = ["-L"];
    dates = "02:00";
    randomizedDelaySec = "45min";
  };

  # Automatically update flake inputs to latest (nix flake update)
  # This runs at 1:00 AM and updates flake.lock to latest on main branches
  systemd.services.flake-autoupdate = {
    description = "Update Nix flake inputs to latest";
    path = [pkgs.git pkgs.nix];
    serviceConfig = {
      Type = "oneshot";
      User = "monkey";
      Environment = "HOME=/home/monkey";
      WorkingDirectory = "/home/monkey/repos/nix";
      ExecStart = "${pkgs.nix}/bin/nix flake update";
    };
  };

  systemd.timers.flake-autoupdate = {
    description = "Timer for flake autoupdate";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "01:00";
      RandomizedDelaySec = "30min";
    };
  };
}
