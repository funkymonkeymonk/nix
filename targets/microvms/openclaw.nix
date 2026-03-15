# openclaw.nix - OpenClaw AI Assistant MicroVM
# A self-hosted personal AI assistant accessible via multiple channels
# Configured to connect to local Matrix server
# Environment files are generated from individual secrets at runtime
# https://github.com/openclaw/openclaw
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Import the OpenClaw service module
  imports = [
    ../../modules/services/openclaw
  ];

  networking.hostName = "openclaw";

  # Disable auto-upgrade for microvm
  system.autoUpgrade.enable = lib.mkForce false;

  # Script to generate environment file from individual secrets
  environment.etc."openclaw/generate-env.sh" = {
    text = ''
      #!/bin/bash
      # Generate OpenClaw environment file from individual secrets
      MATRIX_TOKEN=$(cat /run/secrets/openclaw-matrix-access-token)
      ZEN_KEY=$(cat /run/secrets/openclaw-zen-api-key)
      echo "OPENCLAW_MATRIX_ACCESS_TOKEN=$MATRIX_TOKEN"
      echo "ZEN_API_KEY=$ZEN_KEY"
    '';
    mode = "0750";
    user = "root";
    group = "root";
  };

  # OpenClaw service configuration with Matrix integration
  services.openclaw = {
    enable = true;
    port = 18789;
    openFirewall = true;
    
    # Use the existing 'dev' user from mkMicrovm helper
    user = "dev";
    group = "users";
    dataDir = "/home/dev";
    
    # Generate environment file at service start
    environmentFile = "/run/openclaw/generated-env";
    
    # OpenClaw configuration with Matrix channel
    extraConfig = {
      # Default agent configuration
      agent = {
        model = "zen/default";
      };
      
      # Gateway configuration
      gateway = {
        bind = "0.0.0.0";
        verbose = true;
      };
      
      # Matrix channel configuration
      # Credentials loaded from generated environment file
      channels = {
        matrix = {
          enabled = true;
          homeserver = "http://matrix:8008";  # Internal DNS to Matrix microvm
          userId = "@openclaw:matrix.local";
          # Access token loaded from OPENCLAW_MATRIX_ACCESS_TOKEN env var
          # Room allowlist configured in env file
        };
      };
    };
  };

  # Systemd service to generate environment file before OpenClaw starts
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
      # Ensure directory exists
      mkdir -p /run/openclaw
      
      # Generate environment file from individual secrets
      MATRIX_TOKEN=$(cat /run/secrets/openclaw-matrix-access-token 2>/dev/null || echo "placeholder_token")
      ZEN_KEY=$(cat /run/secrets/openclaw-zen-api-key 2>/dev/null || echo "zen_placeholder")
      
      echo "OPENCLAW_MATRIX_ACCESS_TOKEN=$MATRIX_TOKEN" > /run/openclaw/generated-env
      echo "ZEN_API_KEY=$ZEN_KEY" >> /run/openclaw/generated-env
      
      chmod 600 /run/openclaw/generated-env
      
      echo "Generated environment file with:"
      echo "  - Matrix access token: ''${MATRIX_TOKEN:0:20}..."
      echo "  - Zen API key: ''${ZEN_KEY:0:20}..."
    '';
  };

  # Opnix secrets configuration - store individual secrets
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";

    secrets = {
      # OpenCode Zen API key for OpenClaw (individual secret)
      openclawZenKey = {
        reference = "op://Homelab/OpenClaw/zen-api-key";
        path = "/run/secrets/openclaw-zen-api-key";
        mode = "0600";
        owner = "dev";
        services = ["openclaw-generate-env" "openclaw-gateway"];
      };

      # Matrix access token for OpenClaw bot (individual secret)
      openclawMatrixToken = {
        reference = "op://Homelab/OpenClaw/matrix-access-token";
        path = "/run/secrets/openclaw-matrix-access-token";
        mode = "0600";
        owner = "dev";
        services = ["openclaw-generate-env" "openclaw-gateway"];
      };
    };
  };

  # Additional system packages
  environment.systemPackages = with pkgs; [
    vim
    git
    gh
    htop
    curl
    jq
  ];

  # Root SSH access for management
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8"
  ];

  # Time zone
  time.timeZone = "America/New_York";

  # System state version
  system.stateVersion = "25.05";
}
