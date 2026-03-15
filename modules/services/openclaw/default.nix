# OpenClaw AI Assistant Service Module
# https://github.com/openclaw/openclaw
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.openclaw;
  
  # Wrapper script for openclaw command
  openclawCli = pkgs.writeShellScriptBin "openclaw" ''
    export PATH="${cfg.nodePackage}/bin:${pkgs.git}/bin:$HOME/.npm-global/bin:$PATH"
    export HOME="${cfg.dataDir}"
    
    # Ensure npm global bin is in PATH
    if [ -d "$HOME/.npm-global/bin" ]; then
      export PATH="$HOME/.npm-global/bin:$PATH"
    fi
    
    exec ${cfg.nodePackage}/bin/npx openclaw@latest "$@"
  '';
in {
  options.services.openclaw = {
    enable = mkEnableOption "OpenClaw AI Assistant";

    package = mkOption {
      type = types.package;
      default = pkgs.nodejs_22;
      description = "Node.js package to use for running OpenClaw";
    };

    nodePackage = mkOption {
      type = types.package;
      default = pkgs.nodejs_22;
      description = "Node.js package version (must be >= 22)";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/openclaw";
      description = "Directory where OpenClaw stores its data";
    };

    user = mkOption {
      type = types.str;
      default = "openclaw";
      description = "User account under which OpenClaw runs";
    };

    group = mkOption {
      type = types.str;
      default = "openclaw";
      description = "Group under which OpenClaw runs";
    };

    port = mkOption {
      type = types.port;
      default = 18789;
      description = "Port for the OpenClaw Gateway WebSocket";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open the firewall for OpenClaw ports";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to environment file for OpenClaw configuration.
        Use this for sensitive values like API keys.
      '';
    };

    extraConfig = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        Extra configuration for OpenClaw (written to openclaw.json).
        See https://docs.openclaw.ai/gateway/configuration for options.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Create user and group if needed
    users.users.${cfg.user} = lib.mkIf (cfg.user != "dev") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = true;
      description = "OpenClaw AI Assistant service user";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.user != "dev") {};

    # Install openclaw CLI wrapper system-wide
    environment.systemPackages = [openclawCli];

    # Create data directory structure
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/.openclaw 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/.openclaw/workspace 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/.npm-global 0750 ${cfg.user} ${cfg.group} -"
    ];

    # Write configuration file
    environment.etc."openclaw/config.json" = mkIf (cfg.extraConfig != {}) {
      text = builtins.toJSON cfg.extraConfig;
      mode = "0640";
      user = cfg.user;
      group = cfg.group;
    };

    # OpenClaw Gateway service
    systemd.services.openclaw-gateway = {
      description = "OpenClaw AI Assistant Gateway";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;

        # Setup script - ensures openclaw is installed
        ExecStartPre = pkgs.writeShellScript "openclaw-setup" (
          ''
            export PATH="${cfg.nodePackage}/bin:${pkgs.git}/bin:${pkgs.npm}/bin:$PATH"
            export HOME="${cfg.dataDir}"
            export NPM_CONFIG_PREFIX="${cfg.dataDir}/.npm-global"
            
            # Create npm global directory if it doesn't exist
            mkdir -p "${cfg.dataDir}/.npm-global"
            
            # Configure npm to use local prefix
            ${pkgs.npm}/bin/npm config set prefix "${cfg.dataDir}/.npm-global"
            
            # Check if we need to install openclaw
            if [ ! -f "${cfg.dataDir}/.npm-global/bin/openclaw" ]; then
              echo "Installing OpenClaw..."
              ${pkgs.npm}/bin/npm install -g openclaw@latest
            fi
            
            # Link config if provided
            if [ -f /etc/openclaw/config.json ]; then
              cp /etc/openclaw/config.json "${cfg.dataDir}/.openclaw/openclaw.json"
              chown ${cfg.user}:${cfg.group} "${cfg.dataDir}/.openclaw/openclaw.json"
            fi
            
            echo "OpenClaw setup complete"
          ''
          + lib.optionalString (cfg.environmentFile != null) ''
            # Load environment file
            set -a
            source ${cfg.environmentFile}
            set +a
          ''
        );

        # Start script
        ExecStart = pkgs.writeShellScript "openclaw-start" ''
          export PATH="${cfg.nodePackage}/bin:${pkgs.git}/bin:${cfg.dataDir}/.npm-global/bin:$PATH"
          export HOME="${cfg.dataDir}"
          export NPM_CONFIG_PREFIX="${cfg.dataDir}/.npm-global"
          
          # Set Node memory limit (helpful for microvms)
          export NODE_OPTIONS="--max-old-space-size=3072"
          
          cd ${cfg.dataDir}
          
          # Start the gateway
          exec ${cfg.dataDir}/.npm-global/bin/openclaw gateway --port ${toString cfg.port} --verbose
        '';

        Restart = "always";
        RestartSec = "30";

        # Resource limits
        MemoryMax = "3G";
        CPUQuota = "80%";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [cfg.dataDir];
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        PrivateDevices = false; # May need devices for voice
        RestrictNamespaces = false; # May need for sandboxing
      };

      environment = {
        HOME = cfg.dataDir;
        NODE_PATH = "${cfg.nodePackage}/lib/node_modules";
        NPM_CONFIG_PREFIX = "${cfg.dataDir}/.npm-global";
      };
    };

    # Firewall configuration
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.port # OpenClaw Gateway
        3000 # Optional web interface
      ];
    };
  };
}
