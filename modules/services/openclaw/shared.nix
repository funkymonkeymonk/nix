# Shared OpenClaw configuration module
# Used by microvms, type-server, and darwin-server
{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.openclaw;
in {
  options.myConfig.openclaw = {
    enable = lib.mkEnableOption "OpenClaw AI Assistant with shared configuration";

    user = lib.mkOption {
      type = lib.types.str;
      default = "agent";
      description = "User account under which OpenClaw runs (defaults to agent user)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 18789;
      description = "Port for the OpenClaw Gateway";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the firewall for OpenClaw ports";
    };

    matrix = {
      enable = lib.mkEnableOption "Matrix integration for OpenClaw";

      homeserver = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:8008";
        description = "Matrix homeserver URL";
      };

      userId = lib.mkOption {
        type = lib.types.str;
        default = "@openclaw:localhost";
        description = "Matrix user ID for OpenClaw bot";
      };

      accessTokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to file containing Matrix access token";
      };
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "zen/default";
      description = "Default AI model for OpenClaw agent";
    };

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = "Environment files for OpenClaw (API keys, etc.)";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Additional OpenClaw configuration (merged with defaults)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable agent user if using default agent account
    myConfig.agentUser.enable = lib.mkIf (cfg.user == "agent") true;

    # Configure the official nix-openclaw gateway service
    services.openclaw-gateway = {
      enable = true;
      inherit (cfg) port user;
      group = cfg.user;

      # Environment files for secrets (user-provided + generated if matrix token file is set)
      environmentFiles = cfg.environmentFiles ++ lib.optionals (cfg.matrix.accessTokenFile != null) ["/run/openclaw/generated-env"];

      # Base configuration
      config =
        lib.recursiveUpdate {
          agent = {
            inherit (cfg) model;
          };

          gateway = {
            bind = "0.0.0.0";
            verbose = true;
          };

          channels = lib.mkIf cfg.matrix.enable {
            matrix = {
              enabled = true;
              inherit (cfg.matrix) homeserver userId;
            };
          };
        }
        cfg.extraConfig;
    };

    # Firewall configuration
    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.port
        3000 # Optional web interface
      ];
    };

    # Generate environment file from secrets if configured
    systemd.services.openclaw-generate-env = lib.mkIf (cfg.matrix.accessTokenFile != null) {
      description = "Generate OpenClaw environment file from secrets";
      after = ["onepassword-secrets.service"];
      before = ["openclaw-gateway.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.user;
      };

      script = ''
        mkdir -p /run/openclaw

        MATRIX_TOKEN=$(cat ${cfg.matrix.accessTokenFile} 2>/dev/null || echo "placeholder_token")

        echo "OPENCLAW_MATRIX_ACCESS_TOKEN=$MATRIX_TOKEN" > /run/openclaw/generated-env
        chmod 600 /run/openclaw/generated-env
        chown ${cfg.user}:${cfg.user} /run/openclaw/generated-env
      '';
    };
  };
}
