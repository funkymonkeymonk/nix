# OpenClaw AI Assistant Service Module - Darwin (macOS) version
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

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Host address to bind the OpenClaw Gateway WebSocket (0.0.0.0 for all interfaces)";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to open the firewall for OpenClaw ports (NixOS only)";
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
    # Install openclaw CLI wrapper system-wide
    environment.systemPackages = [openclawCli];

    # Write configuration file
    environment.etc."openclaw/config.json" = mkIf (cfg.extraConfig != {}) {
      text = builtins.toJSON cfg.extraConfig;
    };

    # Create user if needed
    users.users.${cfg.user} = mkIf (cfg.user != "root") {
      isHidden = false;
      home = mkForce cfg.dataDir;
      createHome = true;
      description = "OpenClaw service user";
    };

    # OpenClaw Gateway service (launchd)
    launchd.daemons.openclaw-gateway = {
      serviceConfig = {
        Label = "com.funkymonkeymonk.openclaw-gateway";
        ProgramArguments = [
          "${pkgs.bash}/bin/bash"
          "-c"
          ''
            set -euo pipefail

            export PATH="${cfg.nodePackage}/bin:${pkgs.git}/bin:${cfg.dataDir}/.npm-global/bin:/usr/local/bin:/usr/bin:/bin"
            export HOME="${cfg.dataDir}"
            export NPM_CONFIG_PREFIX="${cfg.dataDir}/.npm-global"

            # Create directories
            mkdir -p "${cfg.dataDir}/.npm-global"
            mkdir -p "${cfg.dataDir}/.openclaw/workspace"

            # Configure npm
            ${cfg.nodePackage}/bin/npm config set prefix "${cfg.dataDir}/.npm-global"

            # Install openclaw if needed
            if [ ! -f "${cfg.dataDir}/.npm-global/bin/openclaw" ]; then
              echo "Installing OpenClaw..."
              ${cfg.nodePackage}/bin/npm install -g openclaw@latest
            fi

            # Link config if provided
            if [ -f /etc/openclaw/config.json ]; then
              cp /etc/openclaw/config.json "${cfg.dataDir}/.openclaw/openclaw.json"
            fi

            # Set Node memory limit
            export NODE_OPTIONS="--max-old-space-size=3072"

            ${optionalString (cfg.environmentFile != null) ''
              # Load environment file
              set -a
              source ${cfg.environmentFile}
              set +a
            ''}

            # Start the gateway
            exec ${cfg.dataDir}/.npm-global/bin/openclaw gateway --port ${toString cfg.port} --host ${cfg.host} --verbose
          ''
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/var/log/openclaw-gateway.log";
        StandardErrorPath = "/var/log/openclaw-gateway.error.log";
        WorkingDirectory = cfg.dataDir;
        EnvironmentVariables = {
          HOME = cfg.dataDir;
          NODE_PATH = "${cfg.nodePackage}/lib/node_modules";
          NPM_CONFIG_PREFIX = "${cfg.dataDir}/.npm-global";
          PATH = "${cfg.nodePackage}/bin:${pkgs.git}/bin:${cfg.dataDir}/.npm-global/bin:/usr/local/bin:/usr/bin:/bin";
        };
      };
    };

    system.activationScripts.postActivation.text = mkAfter ''
      if launchctl list "com.funkymonkeymonk.openclaw-gateway" >/dev/null 2>&1; then
        if launchctl list "com.funkymonkeymonk.openclaw-gateway" 2>&1 | grep -q '"PID"'; then
          echo "  com.funkymonkeymonk.openclaw-gateway: running" >&2
        else
          echo "  com.funkymonkeymonk.openclaw-gateway: loaded (not running)" >&2
        fi
      else
        echo "  com.funkymonkeymonk.openclaw-gateway: not registered" >&2
      fi
    '';
  };
}
