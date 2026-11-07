{
  config,
  inputs,
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

  # Disko provisions the Patriot OS disk and Samsung NVMe cache. The existing
  # media ZFS mirror remains outside the Disko layout.

  myConfig =
    mkUser "monkey" "me@willweaver.dev"
    // {
      skills.superpowersPath = inputs.superpowers;
      roles.developer.enable = true;
      tailscale.enable = true;
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
      };
    };
}
