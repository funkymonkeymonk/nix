# modules/roles/openclaw-server.nix
# Shared OpenClaw AI Gateway configuration
# Can be used by MicroVMs, Lume VMs, or bare metal NixOS
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.roles.openclawServer;
in {
  options.myConfig.roles.openclawServer = {
    enable = mkEnableOption "OpenClaw AI Gateway server configuration";

    port = mkOption {
      type = types.port;
      default = 18789;
      description = "Port for OpenClaw Gateway WebSocket";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/openclaw";
      description = "Directory for OpenClaw data";
    };

    user = mkOption {
      type = types.str;
      default = "openclaw";
      description = "User to run OpenClaw as";
    };

    group = mkOption {
      type = types.str;
      default = "openclaw";
      description = "Group for OpenClaw user";
    };

    agentModel = mkOption {
      type = types.str;
      default = "zen/default";
      description = "Default AI model for agents";
    };

    matrixChannel = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Matrix channel integration";
      };

      homeserver = mkOption {
        type = types.str;
        default = "http://localhost:8008";
        description = "Matrix homeserver URL";
      };

      userId = mkOption {
        type = types.str;
        default = "@openclaw:localhost";
        description = "Matrix user ID for OpenClaw bot";
      };
    };

    discordChannel = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Discord channel integration";
      };

      tokenFile = mkOption {
        type = types.path;
        description = "Path to Discord bot token file";
      };

      allowFrom = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Discord user IDs allowed to interact with bot";
      };
    };

    secrets = {
      zenApiKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to Zen API key file";
      };

      matrixTokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to Matrix access token file";
      };
    };

    extraConfig = mkOption {
      type = types.attrs;
      default = {};
      description = "Additional OpenClaw configuration";
    };
  };

  # Import the OpenClaw service module at the top level
  imports = [
    ../services/openclaw
  ];

  config = mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.dataDir;
      createHome = true;
      description = "OpenClaw service user";
    };

    users.groups.${cfg.group} = {};

    # Configure OpenClaw service
    services.openclaw = {
      enable = true;
      inherit (cfg) port dataDir user group;
      openFirewall = true;

      extraConfig = mkMerge [
        {
          agent.model = cfg.agentModel;
          gateway = {
            bind = "0.0.0.0";
            verbose = true;
          };
        }
        (mkIf cfg.matrixChannel.enable {
          channels.matrix = {
            enabled = true;
            inherit (cfg.matrixChannel) homeserver userId;
          };
        })
        (mkIf cfg.discordChannel.enable {
          channels.discord = {
            enabled = true;
            inherit (cfg.discordChannel) tokenFile allowFrom;
          };
        })
        cfg.extraConfig
      ];

      # Security hardening suitable for containerized/VM environments
      hardening = {
        protectHome = "read-only";
        restrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_NETLINK"];
        lockPersonality = true;
      };
    };

    # Generate environment file from secrets if provided
    systemd.services.openclaw-generate-env = mkIf (cfg.secrets.zenApiKeyFile != null || cfg.secrets.matrixTokenFile != null) {
      description = "Generate OpenClaw environment file from secrets";
      after = ["network.target"];
      before = ["openclaw-gateway.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
      };

      script = ''
        mkdir -p /run/openclaw

        ${optionalString (cfg.secrets.matrixTokenFile != null) ''
          MATRIX_TOKEN=$(cat "${cfg.secrets.matrixTokenFile}" 2>/dev/null || echo "placeholder_token")
          echo "OPENCLAW_MATRIX_ACCESS_TOKEN=$MATRIX_TOKEN" > /run/openclaw/generated-env
        ''}

        ${optionalString (cfg.secrets.zenApiKeyFile != null) ''
          ZEN_KEY=$(cat "${cfg.secrets.zenApiKeyFile}" 2>/dev/null || echo "zen_placeholder")
          ${
            if cfg.secrets.matrixTokenFile != null
            then "echo"
            else "echo \"OPENCLAW_MATRIX_ACCESS_TOKEN=placeholder\" > /run/openclaw/generated-env; echo"
          } "ZEN_API_KEY=$ZEN_KEY" >> /run/openclaw/generated-env
        ''}

        chmod 600 /run/openclaw/generated-env
      '';
    };

    # Point OpenClaw to generated env file if we have secrets
    services.openclaw.environmentFile =
      mkIf (cfg.secrets.zenApiKeyFile != null || cfg.secrets.matrixTokenFile != null)
      "/run/openclaw/generated-env";

    # Standard tools for OpenClaw management
    environment.systemPackages = with pkgs; [
      vim
      git
      curl
      jq
    ];
  };
}
