# jj-autosync module: Automatic git/jj repository synchronization
#
# Provides:
# - Background service that fetches/prunes main branch hourly
# - Auto-syncs local main when changes are detected
# - Session mode with configurable fast sync frequency for active development
# - Integration with jj-workspace for OpenCode workspace management
# - Cross-platform notifications for sync failures
{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.jj-autosync or config.myConfig.jj-autosync or {};
  enabled = cfg.enable or false;
  isDarwin =
    if osConfig != null
    then osConfig.myConfig.isDarwin or false
    else pkgs.stdenv.hostPlatform.isDarwin;

  # Configuration values with defaults
  reposDir = cfg.reposDir or "$HOME/repos";
  mainBranch = cfg.mainBranch or "main";
  hourlySync = cfg.hourlySync or true;
  fastSyncInterval = cfg.fastSyncInterval or 300;
  sessionTtlSeconds = cfg.sessionTtlSeconds or 1800; # 30 minutes default
  username = cfg.username or "";

  # Read shared library content from external file
  # Strip the shebang/header comments and function definitions are sourced inline
  sharedLibContent = builtins.readFile ./jj-autosync-lib.sh;

  # Helper to inline shared lib into a script body (replacing the @SHARED_LIB@ marker)
  withSharedLib = scriptContent:
    builtins.replaceStrings
    ["# @SHARED_LIB@"]
    [sharedLibContent]
    scriptContent;

  # Read script bodies from external .sh files and inline the shared library
  jjAutosyncContent = withSharedLib (builtins.readFile ./jj-autosync.sh);
  jjWorkspaceSessionContent = withSharedLib (builtins.readFile ./jj-workspace-session.sh);
  jjFastSyncContent = withSharedLib (builtins.readFile ./jj-fast-sync.sh);
  jjAutosyncStatusContent = builtins.readFile ./jj-autosync-status.sh;

  # Build PATH that includes user profile
  servicePath =
    if isDarwin
    then "/Users/${username}/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
    else "$HOME/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin";
in {
  config = mkIf enabled {
    # Assertions
    assertions = [
      {
        assertion = !isDarwin || username != "";
        message = "jj-autosync.username is required on Darwin for launchd services";
      }
    ];

    # Install the scripts as executables
    home.packages =
      [
        (pkgs.writeShellScriptBin "jj-autosync" jjAutosyncContent)
        (pkgs.writeShellScriptBin "jj-workspace-session" jjWorkspaceSessionContent)
        (pkgs.writeShellScriptBin "jj-fast-sync" jjFastSyncContent)
        (pkgs.writeShellScriptBin "jj-autosync-status" jjAutosyncStatusContent)
        # Cross-platform notification tool
        pkgs.noti
      ]
      ++ (
        if isDarwin
        then [pkgs.terminal-notifier]
        else [pkgs.libnotify]
      );

    # launchd agents for macOS
    launchd.agents = mkIf isDarwin {
      # Hourly sync for all repos
      jj-autosync = mkIf hourlySync {
        enable = true;
        config = {
          ProgramArguments = ["${pkgs.writeShellScript "jj-autosync" jjAutosyncContent}"];
          StartInterval = 3600; # 1 hour
          RunAtLoad = true;
          StandardOutPath = "/tmp/jj-autosync-launchd.log";
          StandardErrorPath = "/tmp/jj-autosync-launchd.err";
          EnvironmentVariables = {
            HOME = "/Users/${username}";
            PATH = servicePath;
            JJ_AUTOSYNC_REPOS_DIR = reposDir;
            JJ_AUTOSYNC_MAIN_BRANCH = mainBranch;
            JJ_AUTOSYNC_SESSION_TTL = toString sessionTtlSeconds;
            JJ_AUTOSYNC_FAST_SYNC_INTERVAL = toString fastSyncInterval;
          };
        };
      };

      # Fast sync for active sessions
      jj-fast-sync = {
        enable = true;
        config = {
          ProgramArguments = ["${pkgs.writeShellScript "jj-fast-sync" jjFastSyncContent}"];
          StartInterval = fastSyncInterval;
          RunAtLoad = true; # Runs but exits immediately if no sessions
          StandardOutPath = "/tmp/jj-fast-sync-launchd.log";
          StandardErrorPath = "/tmp/jj-fast-sync-launchd.err";
          EnvironmentVariables = {
            HOME = "/Users/${username}";
            PATH = servicePath;
            JJ_AUTOSYNC_SESSION_TTL = toString sessionTtlSeconds;
            JJ_AUTOSYNC_FAST_SYNC_INTERVAL = toString fastSyncInterval;
          };
        };
      };
    };

    # systemd user services for Linux
    systemd.user.services = mkIf (!isDarwin) {
      jj-autosync = mkIf hourlySync {
        Unit = {
          Description = "jj repository auto-sync (hourly)";
          After = ["network-online.target"];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "jj-autosync" jjAutosyncContent}";
          Environment = [
            "HOME=%h"
            "PATH=%h/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
            "JJ_AUTOSYNC_REPOS_DIR=${reposDir}"
            "JJ_AUTOSYNC_MAIN_BRANCH=${mainBranch}"
            "JJ_AUTOSYNC_SESSION_TTL=${toString sessionTtlSeconds}"
            "JJ_AUTOSYNC_FAST_SYNC_INTERVAL=${toString fastSyncInterval}"
          ];
        };
      };

      jj-fast-sync = {
        Unit = {
          Description = "jj repository fast sync for active sessions";
          After = ["network-online.target"];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "jj-fast-sync" jjFastSyncContent}";
          Environment = [
            "HOME=%h"
            "PATH=%h/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
            "JJ_AUTOSYNC_SESSION_TTL=${toString sessionTtlSeconds}"
            "JJ_AUTOSYNC_FAST_SYNC_INTERVAL=${toString fastSyncInterval}"
          ];
        };
      };
    };

    systemd.user.timers = mkIf (!isDarwin) {
      jj-autosync = mkIf hourlySync {
        Unit = {
          Description = "Hourly jj auto-sync timer";
        };
        Timer = {
          OnCalendar = "hourly";
          Persistent = true;
        };
        Install = {
          WantedBy = ["timers.target"];
        };
      };

      jj-fast-sync = {
        Unit = {
          Description = "Fast jj sync timer for active sessions";
        };
        Timer = {
          OnUnitActiveSec = "${toString fastSyncInterval}s";
          OnBootSec = "5min";
          Persistent = true;
        };
        Install = {
          WantedBy = ["timers.target"];
        };
      };
    };
  };
}
