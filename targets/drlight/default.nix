{
  inputs,
  mkUser,
  ...
}: {
  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostId = "f2ec5664";

  fileSystems."/" = {
    device = "/dev/disk/by-label/drlight-root";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/drlight-boot";
    fsType = "vfat";
  };

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      skills.superpowersPath = inputs.superpowers;
      roles.developer.enable = true;
      tailscale.enable = true;
      homepage.enable = true;
      mediaConfig.enable = true;
      backup = {
        enable = true;
        repository = "s3:https://fa5cd9ae588234f20b8889e7619ad6ad.r2.cloudflarestorage.com/personal-backups/drlight";
        paths = ["/var/lib/nixarr"];
      };
      caddy = {
        enable = true;
        cloudflareApiTokenPath = "/run/secrets/cloudflare-api-token";
        apps.jellyfin = {
          host = "jellyfin.home.buildingbananas.com";
          upstream = "http://127.0.0.1:8096";
        };
        apps.seerr = {
          host = "seerr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:5055";
        };
        apps.sonarr = {
          host = "sonarr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:8989";
        };
        apps.radarr = {
          host = "radarr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:7878";
        };
        apps.prowlarr = {
          host = "prowlarr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:9696";
        };
        apps.bazarr = {
          host = "bazarr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:6767";
        };
        apps.audiobookshelf = {
          host = "audiobookshelf.home.buildingbananas.com";
          upstream = "http://127.0.0.1:9292";
        };
        apps.lidarr = {
          host = "lidarr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:8686";
        };
        apps.shelfmark = {
          host = "shelfmark.home.buildingbananas.com";
          upstream = "http://127.0.0.1:8084";
        };
        apps.transmission = {
          host = "transmission.home.buildingbananas.com";
          upstream = "http://127.0.0.1:9091";
          webRoot = "/transmission/web";
        };
        apps.dashboard = {
          host = "dashboard.home.buildingbananas.com";
          upstream = "http://127.0.0.1:8082";
        };
      };
      onepassword = {
        enable = true;
        defaultVault = "Homelab";
        secrets.jellyfinAdminPassword = {
          reference = "zero-jellyfin-admin/password";
          path = "/run/secrets/jellyfin-admin-password";
          mode = "0400";
          services = ["jellyfin-declarative-config"];
        };
        secrets.cloudflareApiToken = {
          reference = "cloudflare.com/dns-api-token";
          path = "/run/secrets/cloudflare-api-token";
          mode = "0400";
          owner = "root";
          group = "root";
          services = ["caddy-cloudflare-env" "caddy"];
        };
        secrets.drlightResticPassword = {
          reference = "zero-restic/password";
          path = "/run/secrets/drlight-restic-password";
          mode = "0400";
          services = ["restic-backup-env" "restic-backups-drlight"];
        };
      };
    };
}
