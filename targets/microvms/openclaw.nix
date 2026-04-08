# openclaw.nix - OpenClaw AI Assistant MicroVM
# Secrets come from 1Password via opnix
# https://github.com/openclaw/openclaw
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ../../modules/services/openclaw
  ];

  networking.hostName = "openclaw";

  system.autoUpgrade.enable = lib.mkForce false;

  # Microvm-specific network config
  myConfig.microvm = {
    enable = true;
    ipAddress = "192.168.83.16";
    gateway = "192.168.83.1";
  };

  services.openclaw = {
    enable = true;
    port = 18789;
    openFirewall = true;

    user = "dev";
    group = "users";
    dataDir = "/home/dev";

    # Secrets loaded from opnix at /run/secrets/
    environmentFile = "/run/openclaw/generated-env";

    extraConfig = {
      agent = {
        model = "zen/default";
      };

      gateway = {
        bind = "0.0.0.0";
        verbose = true;
      };

      channels = {
        matrix = {
          enabled = true;
          homeserver = "http://192.168.83.15:8008";
          userId = "@openclaw:matrix.local";
        };
      };
    };

    # Additional hardening for microvm environment
    hardening = {
      protectHome = "read-only";
      restrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_NETLINK"];
      lockPersonality = true;
    };
  };

  # Generate env file from opnix secrets at boot
  systemd.services.openclaw-generate-env = {
    description = "Generate OpenClaw environment file from secrets";
    after = ["onepassword-secrets.service"];
    before = ["openclaw-gateway.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "dev";
      Group = "users";
    };

    script = ''
      mkdir -p /run/openclaw

      MATRIX_TOKEN=$(cat /run/secrets/openclaw-matrix-access-token 2>/dev/null || echo "placeholder_token")
      ZEN_KEY=$(cat /run/secrets/openclaw-zen-api-key 2>/dev/null || echo "zen_placeholder")

      echo "OPENCLAW_MATRIX_ACCESS_TOKEN=$MATRIX_TOKEN" > /run/openclaw/generated-env
      echo "ZEN_API_KEY=$ZEN_KEY" >> /run/openclaw/generated-env

      chmod 600 /run/openclaw/generated-env
    '';
  };

  # Opnix secrets configuration
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";

    secrets = {
      openclawZenKey = {
        reference = "op://Homelab/OpenClaw/zen-api-key";
        path = "/run/secrets/openclaw-zen-api-key";
        mode = "0600";
        owner = "dev";
        services = ["openclaw-generate-env" "openclaw-gateway"];
      };

      openclawMatrixToken = {
        reference = "op://Homelab/OpenClaw/matrix-access-token";
        path = "/run/secrets/openclaw-matrix-access-token";
        mode = "0600";
        owner = "dev";
        services = ["openclaw-generate-env" "openclaw-gateway"];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    gh
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
