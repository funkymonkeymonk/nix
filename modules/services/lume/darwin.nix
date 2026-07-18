# Lume service module for Darwin (macOS)
# Manages Lume VM runtime as a launchd service
# https://cua.ai/docs/lume
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.lume;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  homeDir = commonLib.darwinHomeDir config;
in {
  options.myConfig.lume = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Lume macOS VM runtime";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.lume;
      description = "Lume package to use";
    };

    enableBackgroundService = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Lume background service (lume serve)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7777;
      description = "Port for Lume HTTP API";
    };

    enableAutoUpdater = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic Lume updates";
    };

    prePullImages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of VM images to pre-pull on activation (e.g., macos-tahoe-vanilla:latest)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # Lume background service (lume serve)
    launchd.daemons.lume = lib.mkIf cfg.enableBackgroundService {
      command = "${cfg.package}/bin/lume serve --port ${toString cfg.port}";
      serviceConfig = {
        Label = "com.trycua.lume_daemon";
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/lume_daemon.log";
        StandardErrorPath = "/tmp/lume_daemon.err";
        EnvironmentVariables = {
          HOME = homeDir;
          USER = primaryUser;
          PATH = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${cfg.package}/bin";
        };
      };
    };

    # Auto-updater service
    launchd.daemons.lume-updater = lib.mkIf cfg.enableAutoUpdater {
      command = "${cfg.package}/bin/lume-update";
      serviceConfig = {
        Label = "com.trycua.lume_updater";
        StartCalendarInterval = {
          Hour = 3;
          Minute = 0;
        };
        StandardOutPath = "/tmp/lume_updater.log";
        StandardErrorPath = "/tmp/lume_updater.err";
        EnvironmentVariables = {
          HOME = homeDir;
          USER = primaryUser;
        };
      };
    };

    # Pre-pull VM images on activation
    system.activationScripts.lume-images = lib.mkIf (cfg.prePullImages != []) {
      text = ''
        echo "Pre-pulling Lume VM images..."
        export HOME="${homeDir}"
        export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${cfg.package}/bin"

        ${lib.concatMapStrings (image: ''
            echo "Pulling ${image}..."
            if ! ${cfg.package}/bin/lume images 2>/dev/null | grep -q "${image}"; then
              ${cfg.package}/bin/lume pull "${image}" || echo "Warning: Failed to pull ${image}"
            else
              echo "  ${image} already exists, skipping"
            fi
          '')
          cfg.prePullImages}
      '';
    };
  };
}
