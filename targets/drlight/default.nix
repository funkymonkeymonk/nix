{
  _config,
  pkgs,
  _lib,
  inputs,
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

  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = [
      "-L" # print build logs
    ];
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
