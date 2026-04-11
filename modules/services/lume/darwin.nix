# Lume service module for Darwin (macOS)
# Manages Lume VM runtime as a launchd service
# https://cua.ai/docs/lume
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.lume;

  # Get the first configured user for launchd environment
  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "root";

  # Default home directory
  homeDir = "/Users/${primaryUser}";
in {
  options.myConfig.lume = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Lume macOS VM runtime";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.lume;
      description = "Lume package to use";
    };

    enableBackgroundService = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Lume background service (lume serve)";
    };

    port = mkOption {
      type = types.port;
      default = 7777;
      description = "Port for Lume HTTP API";
    };

    enableAutoUpdater = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic Lume updates";
    };

    prePullImages = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of VM images to pre-pull on activation (e.g., macos-tahoe-vanilla:latest)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # Lume background service (lume serve)
    launchd.daemons.lume = mkIf cfg.enableBackgroundService {
      serviceConfig = {
        Label = "com.trycua.lume_daemon";
        ProgramArguments = ["${cfg.package}/bin/lume" "serve" "--port" "${toString cfg.port}"];
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
    launchd.daemons.lume-updater = mkIf cfg.enableAutoUpdater {
      serviceConfig = {
        Label = "com.trycua.lume_updater";
        ProgramArguments = ["${cfg.package}/bin/lume-update"];
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
    system.activationScripts.lume-images = mkIf (cfg.prePullImages != []) {
      text = ''
        echo "Pre-pulling Lume VM images..."
        export HOME="${homeDir}"
        export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${cfg.package}/bin"

        ${concatMapStrings (image: ''
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
