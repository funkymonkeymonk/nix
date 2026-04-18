# media-center.nix - Media Center MicroVM with Jellyfin
# Media server for streaming movies, TV shows, music, and photos
# https://jellyfin.org/
{
  lib,
  pkgs,
  ...
}: {
  networking.hostName = "media-center";

  system.autoUpgrade.enable = lib.mkForce false;

  # Microvm-specific network config
  myConfig.microvm = {
    enable = true;
    ipAddress = "192.168.83.17";
    gateway = "192.168.83.1";
  };

  # Jellyfin media server
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user = "jellyfin";
    group = "jellyfin";
    dataDir = "/var/lib/jellyfin";
    cacheDir = "/var/cache/jellyfin";
  };

  # Sonarr for TV show management
  services.sonarr = {
    enable = true;
    openFirewall = true;
    user = "sonarr";
    group = "sonarr";
    dataDir = "/var/lib/sonarr";
  };

  # Radarr for movie management
  services.radarr = {
    enable = true;
    openFirewall = true;
    user = "radarr";
    group = "radarr";
    dataDir = "/var/lib/radarr";
  };

  # Lidarr for music management
  services.lidarr = {
    enable = true;
    openFirewall = true;
    user = "lidarr";
    group = "lidarr";
    dataDir = "/var/lib/lidarr";
  };

  # Prowlarr for indexer management
  services.prowlarr = {
    enable = true;
    openFirewall = true;
  };

  # Bazarr for subtitle management
  services.bazarr = {
    enable = true;
    openFirewall = true;
    user = "bazarr";
    group = "bazarr";
  };

  # Transmission for torrent downloads
  services.transmission = {
    enable = true;
    openFirewall = true;
    package = pkgs.transmission_4;
    settings = {
      download-dir = "/var/lib/transmission/Downloads";
      incomplete-dir = "/var/lib/transmission/.incomplete";
      rpc-bind-address = "0.0.0.0";
      rpc-whitelist = "127.0.0.1,192.168.*.*";
    };
  };

  # Create media directories
  systemd.tmpfiles.rules = [
    "d /var/lib/media 0755 root root -"
    "d /var/lib/media/movies 0755 jellyfin jellyfin -"
    "d /var/lib/media/tv 0755 jellyfin jellyfin -"
    "d /var/lib/media/music 0755 jellyfin jellyfin -"
    "d /var/lib/media/photos 0755 jellyfin jellyfin -"
  ];

  # Nginx reverse proxy for easy access
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;

    virtualHosts."media.local" = {
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:8096";
          proxyWebsockets = true;
        };
      };
    };

    # Serve Jellyfin on a dedicated path
    virtualHosts."jellyfin.media.local" = {
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Protocol $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
        '';
      };
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      80 # nginx
      443 # nginx (future TLS)
      8096 # jellyfin
      8920 # jellyfin https
      8989 # sonarr
      7878 # radarr
      8686 # lidarr
      9696 # prowlarr
      6767 # bazarr
      9091 # transmission
      51413 # transmission peer port
    ];
    allowedUDPPorts = [
      51413 # transmission peer port
    ];
  };

  environment.systemPackages = with pkgs; [
    jellyfin
    jellyfin-web
    jellyfin-ffmpeg
    vim
    htop
    curl
    jq
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8"
  ];

  time.timeZone = "America/New_York";
  system.stateVersion = "25.05";
}
