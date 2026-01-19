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

  # systemd configuration
  systemd = {
    tmpfiles.rules = [
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
      "d /srv/media/tubearchivist/es 0755 root root -"
    ];

    services.media-permissions = {
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

    services.tubearchivist-env = {
      description = "Generate TubeArchivist environment file with secrets";
      wantedBy = ["docker-tubearchivist.service"];
      after = ["onepassword-secrets.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/tubearchivist
        chmod 755 /run/tubearchivist

        # Read secrets and create environment file
        if [[ -f /run/secrets/tubearchivist-username && -f /run/secrets/tubearchivist-password ]]; then
          cat > /run/tubearchivist/environment << EOF
        TA_USERNAME=$(cat /run/secrets/tubearchivist-username)
        TA_PASSWORD=$(cat /run/secrets/tubearchivist-password)
        EOF
          chmod 600 /run/tubearchivist/environment
        else
          echo "Warning: TubeArchivist secrets not available, using defaults"
          cat > /run/tubearchivist/environment << EOF
        TA_USERNAME=tubearchivist
        TA_PASSWORD=tubearchivist
        EOF
          chmod 600 /run/tubearchivist/environment
        fi
      '';
    };
  };

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
    secrets = {
      username = "tubearchivist";
      password = "tubearchivist";
    };
  };

  # Configure OpNix for 1Password secrets
  services.onepassword-secrets = {
    enable = true;
    secrets = {
      tubearchivistUsername = {
        reference = "op://Homelab/Tubearchivist/username";
        path = "/run/secrets/tubearchivist-username";
        mode = "0400";
        owner = "root";
        group = "root";
      };
      tubearchivistPassword = {
        reference = "op://Homelab/Tubearchivist/password";
        path = "/run/secrets/tubearchivist-password";
        mode = "0400";
        owner = "root";
        group = "root";
      };
    };
  };
}
