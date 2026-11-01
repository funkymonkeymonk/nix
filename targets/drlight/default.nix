{
  inputs,
  mkUser,
  ...
}: {
  # Initial monkey SSH access
  users.users.monkey.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8 monkey@MegamanX"
  ];

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
      collector.destinationHostname = "localhost";
      caddy = {
        enable = true;
        cloudflareApiTokenPath = "/run/secrets/cloudflare-api-token";
        apps.jellyfin = {
          host = "jellyfin.home.buildingbananas.com";
          upstream = "http://127.0.0.1:8096";
        };
        apps.grafana = {
          host = "grafana.home.buildingbananas.com";
          upstream = "http://127.0.0.1:3000";
        };
        # TODO: Add remote seed-box routes when that integration is ready.
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
      };
    };
}
