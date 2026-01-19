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
# - Sets up media library for Jellyfin
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Make sure zsh is available system-wide (so the shell path exists)
  environment.systemPackages = with pkgs; [
    zsh
  ];

  # Host/network/time/SSH settings for drlight
  networking = {
    hostName = "drlight";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [9000 8000];
  };
  time.timeZone = "America/New_York";

  services.openssh.enable = true;

  # Media library setup for Jellyfin
  systemd.tmpfiles.rules = [
    "d /srv/media 0755 root root -"
    "d /srv/media/movies 0755 jellyfin jellyfin -"
    "d /srv/media/tv 0755 jellyfin jellyfin -"
    "d /srv/media/music 0755 jellyfin jellyfin -"
    "d /srv/media/photos 0755 jellyfin jellyfin -"
    "d /srv/media/audiobooks 0755 jellyfin jellyfin -"
    "d /srv/media/downloads 0755 jellyfin jellyfin -"
    "d /srv/media/downloads/incoming 0755 jellyfin jellyfin -"
    "d /srv/media/downloads/temp 0755 jellyfin jellyfin -"
    # TubeArchivist directories
    "d /srv/media/tubearchivist 0755 root root -"
    "d /srv/media/tubearchivist/videos 0755 jellyfin jellyfin -"
    "d /srv/media/tubearchivist/cache 0755 root root -"
    "d /srv/media/tubearchivist/redis 0755 root root -"
    "d /srv/media/tubearchivist/es 0755 1000 1000 -"
  ];

  # User configuration
  users = {
    # Ensure the user exists with the desired shell and groups
    users.monkey = {
      isNormalUser = true;
      description = "monkey";
      extraGroups = ["networkmanager" "wheel" "media" "docker"];
      # Use the zsh from nixpkgs as the login shell
      shell = pkgs.zsh;
      # Keep explicit home to match other entries; adjust if you prefer default
      home = "/home/monkey";
    };

    # Create media group for shared access
    groups.media = {};
    users.jellyfin.extraGroups = ["media"];
  };

  # Docker support for TubeArchivist
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # TubeArchivist configuration
  myConfig.tubearchivist = {
    host = "drlight";
  };

  # Set proper permissions on media directories
  systemd.services.media-permissions = {
    description = "Set media directory permissions";
    wantedBy = ["multi-user.target"];
    after = ["systemd-tmpfiles-setup.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = [
        "${pkgs.coreutils}/bin/chgrp -R media /srv/media"
        "${pkgs.coreutils}/bin/chmod -R 2775 /srv/media"
      ];
    };
  };
}
