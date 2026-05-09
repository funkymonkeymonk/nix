# openclaw.nix - OpenClaw AI Assistant MicroVM
# Secrets come from 1Password Connect (REST API)
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

    # Secrets loaded from Connect API
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
        discord = {
          enabled = true;
          tokenFile = "/run/secrets/openclaw-discord-bot-token";
          allowFrom = ["279110923438915586"]; # Your Discord user ID
          dmPolicy = "pairing";
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

  # 1Password Connect configuration
  # Uses REST API instead of opnix service account
  myConfig.onepassword-connect-client = {
    enable = true;
    serverUrl = "http://192.168.83.1:8080";
    tokenFile = "/etc/connect-token";
  };

  # Generate env file from Connect secrets at boot
  systemd.services.openclaw-generate-env = {
    description = "Generate OpenClaw environment file from 1Password Connect";
    after = ["network-online.target"];
    before = ["openclaw-gateway.service"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root"; # Need root to read token file
      Group = "users";
    };

    script = ''
      set -euo pipefail

      mkdir -p /run/openclaw

      CONNECT_URL="http://192.168.83.1:8080"
      TOKEN_FILE="/etc/connect-token"

      # Check if Connect token exists
      if [[ ! -f "$TOKEN_FILE" ]]; then
        echo "WARNING: Connect token not found at $TOKEN_FILE"
        echo "Using placeholder values"

        echo "OPENCLAW_MATRIX_ACCESS_TOKEN=placeholder_token" > /run/openclaw/generated-env
        echo "ZEN_API_KEY=zen_placeholder" >> /run/openclaw/generated-env
        echo "OPENCLAW_DISCORD_BOT_TOKEN=discord_placeholder" >> /run/openclaw/generated-env
        chmod 600 /run/openclaw/generated-env
        chown dev:users /run/openclaw/generated-env
        exit 0
      fi

      TOKEN=$(cat "$TOKEN_FILE")

      # Helper function to fetch secrets from Connect
      fetch_secret() {
        local vault="$1"
        local item="$2"
        local field="$3"

        curl -sf \
          -H "Authorization: Bearer $TOKEN" \
          "$CONNECT_URL/v1/vaults/$vault/items/$item" | \
          ${pkgs.jq}/bin/jq -r ".fields[] | select(.label==\"$field\").value" 2>/dev/null || \
          echo ""
      }

      # Fetch secrets
      echo "Fetching secrets from 1Password Connect..."

      ZEN_KEY=$(fetch_secret "Homelab" "openclaw" "zen-api-key")
      MATRIX_TOKEN=$(fetch_secret "Homelab" "openclaw" "matrix-access-token")
      DISCORD_TOKEN=$(fetch_secret "Homelab" "openclaw" "discord-bot-token")

      # Write environment file
      echo "OPENCLAW_MATRIX_ACCESS_TOKEN=''${MATRIX_TOKEN:-placeholder_token}" > /run/openclaw/generated-env
      echo "ZEN_API_KEY=''${ZEN_KEY:-zen_placeholder}" >> /run/openclaw/generated-env
      echo "OPENCLAW_DISCORD_BOT_TOKEN=''${DISCORD_TOKEN:-discord_placeholder}" >> /run/openclaw/generated-env

      chmod 600 /run/openclaw/generated-env
      chown dev:users /run/openclaw/generated-env

      # Write Discord token to file for OpenClaw
      echo "''${DISCORD_TOKEN:-discord_placeholder}" > /run/secrets/openclaw-discord-bot-token
      chmod 600 /run/secrets/openclaw-discord-bot-token
      chown dev:users /run/secrets/openclaw-discord-bot-token

      echo "Secrets fetched successfully"
    '';
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
