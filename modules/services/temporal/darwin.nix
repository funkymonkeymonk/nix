# Local Temporal development server for Darwin.
# Runs as the primary user so its SQLite state and UI belong to that user.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.temporal;
  commonLib = import ../../common/lib.nix {inherit lib;};
  primaryUser = commonLib.primaryUser config;
  homeDir = commonLib.darwinHomeDir config;
  namespaceArgs = lib.concatMapStringsSep " " (namespace: "--namespace ${lib.escapeShellArg namespace}") cfg.namespaces;
in {
  options.myConfig.temporal = {
    enable = lib.mkEnableOption "local Temporal server";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.temporal-cli;
      description = "Temporal CLI package providing the development server.";
    };

    ip = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Temporal frontend bind address.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7233;
      description = "Temporal frontend gRPC port.";
    };

    uiPort = lib.mkOption {
      type = lib.types.port;
      default = 8233;
      description = "Temporal Web UI port.";
    };

    namespaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["inference"];
      description = "Namespaces to create when the server starts.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "${homeDir}/.local/share/temporal";
      description = "Directory containing Temporal's persistent SQLite state.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.user.agents.temporal = {
      script = ''
        set -euo pipefail
        install -d -m 0755 ${lib.escapeShellArg cfg.stateDir}
        exec ${cfg.package}/bin/temporal server start-dev \
          --log-format=json \
          --ip ${lib.escapeShellArg cfg.ip} \
          --port ${toString cfg.port} \
          --headless=true \
          --ui-ip ${lib.escapeShellArg cfg.ip} \
          --ui-port ${toString cfg.uiPort} \
          ${namespaceArgs} \
          --db-filename ${lib.escapeShellArg "${cfg.stateDir}/temporal.sqlite"}
      '';
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = true;
        WorkingDirectory = homeDir;
        StandardOutPath = "${homeDir}/Library/Logs/temporal/server.log";
        StandardErrorPath = "${homeDir}/Library/Logs/temporal/server.error.log";
        EnvironmentVariables = {
          HOME = homeDir;
          USER = primaryUser;
        };
      };
    };

    system.activationScripts.temporalDirectories.text = ''
      install -d -o ${primaryUser} -g staff -m 0755 \
        "${cfg.stateDir}" \
        "${homeDir}/Library/Logs/temporal"
    '';
  };
}
