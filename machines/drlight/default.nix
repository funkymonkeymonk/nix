{
  config,
  lib,
  mkUser,
  ...
}: let
  sshPublicKey = import ../../library/ssh-public-key.nix;
in {
  # Machines requires root SSH for transactional installation/deployment. Keep
  # it key-only and limited to the same approved public key.
  users.users.root.openssh.authorizedKeys.keys = [sshPublicKey];
  services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
  services.openssh.settings.PasswordAuthentication = false;

  # Preserve the ZFS pool owner's host ID while drlight takes over from zero.
  networking.hostId = "0badc0de";
  boot.zfs.forceImportRoot = false;
  boot.zfs.forceImportAll = false;

  # Drlight is the Tailscale gateway. Keep tailnet-only service ports
  # reachable from the physical home LAN without opening them globally.
  networking.firewall.interfaces.eno1 = {
    allowedTCPPorts = [
      53
      config.myConfig.loki.port
      config.services.radarr.settings.server.port
      config.services.sonarr.settings.server.port
      config.services.lidarr.settings.server.port
      config.services.bazarr.settings.general.port
      config.services.mylar3.port
      config.services.seerr.port
      config.myConfig.nodeExporter.port
    ];
    allowedUDPPorts = [53];
  };

  # Disko provisions the Patriot OS disk and Samsung NVMe cache. The existing
  # media ZFS mirror remains outside the Disko layout.

  # Opnix's secret service already resolves changed values and restarts their
  # dependents. Its output-directory watcher launches a duplicate resolver.
  systemd.paths.opnix-secrets-watcher.enable = lib.mkForce false;

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      roles.developer.enable = true;
      nodeExporter.openFirewallInterfaces = ["tailscale0" "eno1"];
      ultraMediaDownloadStage = {
        enable = true;
        cleanup = {
          enable = true;
          privateTrackerRatioProtection.enable = false;
        };
        remoteDisk = {
          enable = true;
          capacityBytes = 4000000000000;
          warningThresholdBytes = 3000000000000;
        };
      };
      collector.destinationHostname = "localhost";
      caddy = {
        enable = true;
        cloudflareApiTokenPath = "/run/secrets/cloudflare-api-token";
        apps.jellyfin = {
          host = "jellyfin.home.buildingbananas.com";
          upstream = "http://127.0.0.1:8096";
          homepage = {
            title = "Jellyfin";
            group = "Media";
            description = "Media server";
          };
        };
        apps.seerr = {
          host = "seerr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:5055";
          homepage = {
            title = "Seerr";
            group = "Media Management";
            description = "Movie and TV request portal";
          };
        };
        apps.grafana = {
          host = "grafana.home.buildingbananas.com";
          upstream = "http://127.0.0.1:3000";
          homepage = {
            enable = config.services.grafana.enable;
            title = "Grafana";
            group = "Monitoring";
            description = "System monitoring";
            widgets = [
              {
                type = "grafana";
                version = 2;
                url = "http://127.0.0.1:3000";
                username = "{{HOMEPAGE_FILE_GRAFANA_USERNAME}}";
                password = "{{HOMEPAGE_FILE_GRAFANA_PASSWORD}}";
              }
            ];
          };
        };
        # TODO: Add remote seed-box routes when that integration is ready.
        apps.dashboard = {
          host = "dashboard.home.buildingbananas.com";
          upstream = "http://127.0.0.1:8082";
          homepage.enable = false;
        };
        apps.radarr = {
          host = "radarr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}";
          homepage = {
            title = "Radarr";
            group = "Media Management";
            description = "Movie library manager";
          };
        };
        apps.sonarr = {
          host = "sonarr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}";
          homepage = {
            title = "Sonarr";
            group = "Media Management";
            description = "TV series library manager";
          };
        };
        apps.lidarr = {
          host = "lidarr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:${toString config.services.lidarr.settings.server.port}";
          homepage = {
            title = "Lidarr";
            group = "Media Management";
            description = "Music library manager";
          };
        };
        apps.mylar3 = {
          host = "mylar.home.buildingbananas.com";
          upstream = "http://127.0.0.1:${toString config.services.mylar3.port}";
          homepage = {
            title = "Mylar3";
            group = "Media Management";
            description = "Comic book library manager";
          };
        };
        apps.bazarr = {
          host = "bazarr.home.buildingbananas.com";
          upstream = "http://127.0.0.1:${toString config.services.bazarr.settings.general.port}";
          homepage = {
            title = "Bazarr";
            group = "Media Management";
            description = "Subtitle manager";
          };
        };
      };
      onepassword = {
        enable = true;
        defaultVault = "Opnix";
        secrets.cloudflareApiToken = {
          reference = "Cloudflare DNS API Token/credential";
          path = "/run/secrets/cloudflare-api-token";
          mode = "0400";
          owner = "root";
          group = "root";
          services = ["caddy-cloudflare-env" "caddy"];
        };
        secrets.jellyfinDiscordWebhook = {
          reference = "Jellyfin Discord Webhook/url";
          path = "/run/secrets/jellyfin-discord-webhook";
          mode = "0440";
          owner = "root";
          group = "media-auth-jellyfin";
          services = ["jellyfin-discord-webhook-config-sync"];
        };
      };
    };
}
