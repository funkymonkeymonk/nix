# jj-autosync module: Automatic git/jj repository synchronization
#
# Provides:
# - Background service that fetches/prunes main branch hourly
# - Auto-pulls to local main when changes are detected
# - Session mode with 5-minute sync frequency for active development
# - Integration with jj-workspace for OpenCode workspace management
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
    else pkgs.stdenv.isDarwin;

  # Script content as strings (to avoid cross-platform derivation issues)
  jjAutosyncContent = ''
    #!/usr/bin/env bash
    # jj-autosync: Sync main branch with upstream
    # Runs as background service or on-demand
    # Only syncs repos that have a .jj-autosync file (opt-in per repo)
    set -euo pipefail

    # Configuration
    REPOS_DIR="''${JJ_AUTOSYNC_REPOS_DIR:-$HOME/repos}"
    LOG_FILE="''${JJ_AUTOSYNC_LOG:-/tmp/jj-autosync.log}"
    CONFIG_FILE=".jj-autosync"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    }

    # Parse config file (simple key=value format)
    parse_config() {
        local config_file="$1"
        local key="$2"
        local default="$3"

        if [[ -f "$config_file" ]]; then
            local value=$(grep "^$key=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
            echo "''${value:-$default}"
        else
            echo "$default"
        fi
    }

    sync_repo() {
        local repo="$1"
        local repo_name=$(basename "$repo")

        # Check if it's a jj repo
        if [[ ! -d "$repo/.jj" ]]; then
            return 0
        fi

        cd "$repo"

        # Check for opt-in config file
        if [[ ! -f "$CONFIG_FILE" ]]; then
            return 0
        fi

        # Parse config
        local enabled=$(parse_config "$CONFIG_FILE" "enabled" "true")
        local main_branch=$(parse_config "$CONFIG_FILE" "main" "main")

        if [[ "$enabled" != "true" ]]; then
            log "[$repo_name] Sync disabled in config, skipping"
            return 0
        fi

        log "[$repo_name] Starting sync (main=$main_branch)..."

        # Fetch
        if jj git fetch 2>> "$LOG_FILE"; then
            log "[$repo_name] Fetch completed"
        else
            log "[$repo_name] Fetch failed"
            return 1
        fi

        # Check if we're on main (default workspace, no working changes)
        local current_ws=$(jj workspace list 2>/dev/null | grep "^default" || echo "")
        if [[ -n "$current_ws" ]]; then
            # Check if main has new commits
            local local_main=$(jj log -r "$main_branch@" --no-graph -T 'commit_id' 2>/dev/null || echo "none")
            local remote_main=$(jj log -r "$main_branch@origin" --no-graph -T 'commit_id' 2>/dev/null || echo "none")

            if [[ "$local_main" != "$remote_main" && "$remote_main" != "none" ]]; then
                log "[$repo_name] Main branch updated, tracking remote..."
                jj bookmark track "$main_branch@origin" 2>> "$LOG_FILE" || true
            fi
        fi

        log "[$repo_name] Sync complete"
    }

    # Main execution
    log "=== jj-autosync starting ==="

    # Find all jj repos in the repos directory that have opted in
    if [[ -d "$REPOS_DIR" ]]; then
        for repo in "$REPOS_DIR"/*/; do
            if [[ -d "$repo/.jj" && -f "$repo/$CONFIG_FILE" ]]; then
                sync_repo "$repo" || true
            fi
        done
    fi

    log "=== jj-autosync complete ==="
  '';

  jjWorkspaceSessionContent = ''
    #!/usr/bin/env bash
    # jj-workspace-session: Manage workspace sessions with increased sync frequency
    set -euo pipefail

    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    SESSION_DIR="''${HOME}/.local/state/jj-autosync"
    SESSION_FILE="$SESSION_DIR/active-sessions"
    FAST_SYNC_INTERVAL=300  # 5 minutes

    mkdir -p "$SESSION_DIR"

    usage() {
        cat <<EOF
    Usage: jj-workspace-session <command> [args]

    Manage jj workspace sessions with fast sync (every 5 minutes).

    Commands:
      start [name] [base]    Start a session in new workspace (creates workspace if name given)
      stop                   Stop session in current directory
      status                 Show active sessions
      list                   List active sessions
      sync                   Manually trigger sync for current repo

    Examples:
      jj-workspace-session start                    # Start session in current workspace
      jj-workspace-session start feat/auth          # Create workspace and start session
      jj-workspace-session start fix/bug develop    # Create workspace from develop
      jj-workspace-session stop                     # Stop session
    EOF
        exit 1
    }

    generate_id() {
        # Generate short unique id
        echo "$(date +%H%M)-$(head -c 4 /dev/urandom | xxd -p | head -c 4)"
    }

    add_session() {
        local repo_path="$1"
        local workspace_name="$2"
        echo "$repo_path|$workspace_name|$(date +%s)" >> "$SESSION_FILE"
    }

    remove_session() {
        local repo_path="$1"
        if [[ -f "$SESSION_FILE" ]]; then
            grep -v "^$repo_path|" "$SESSION_FILE" > "$SESSION_FILE.tmp" || true
            mv "$SESSION_FILE.tmp" "$SESSION_FILE"
        fi
    }

    is_session_active() {
        local repo_path="$1"
        if [[ -f "$SESSION_FILE" ]]; then
            grep -q "^$repo_path|" "$SESSION_FILE"
            return $?
        fi
        return 1
    }

    cmd_start() {
        local name="''${1:-}"
        local base="''${2:-main}"

        # Ensure we're in a jj repo
        if [[ ! -d ".jj" ]]; then
            echo -e "''${RED}Error: Not in a jj repository''${NC}"
            exit 1
        fi

        local repo_path=$(pwd)
        local workspace_name="default"

        # If name provided, create a workspace
        if [[ -n "$name" ]]; then
            local session_id=$(generate_id)
            local date_str=$(date +%Y%m%d)

            # Parse type/topic format or use as-is
            if [[ "$name" == */* ]]; then
                workspace_name="$name-$date_str-$session_id"
            else
                workspace_name="feat/$name-$date_str-$session_id"
            fi

            echo -e "''${GREEN}Creating workspace: $workspace_name (base: $base)''${NC}"

            # Create workspace directory
            local ws_dir="./workspaces/$(echo "$workspace_name" | tr '/' '-')"
            mkdir -p ./workspaces

            # Add workspaces/ to .gitignore if needed
            if [[ -f .gitignore ]]; then
                if ! grep -q "^workspaces/" .gitignore; then
                    echo "workspaces/" >> .gitignore
                    echo -e "''${YELLOW}Added workspaces/ to .gitignore''${NC}"
                fi
            fi

            # Create the workspace
            jj workspace add "$ws_dir" -r "$base"

            echo -e "''${BLUE}Workspace created at: $ws_dir''${NC}"
            echo -e "''${YELLOW}cd $ws_dir to start working''${NC}"

            # Register session for the workspace directory
            add_session "$(cd "$ws_dir" && pwd)" "$workspace_name"
        else
            # Just start session tracking in current location
            add_session "$repo_path" "$workspace_name"
        fi

        echo -e "''${GREEN}Session started with 5-minute sync interval''${NC}"
        echo -e "Run 'jj-workspace-session stop' when done"
    }

    cmd_stop() {
        local repo_path=$(pwd)

        if ! is_session_active "$repo_path"; then
            echo -e "''${YELLOW}No active session in current directory''${NC}"
            return 0
        fi

        remove_session "$repo_path"
        echo -e "''${GREEN}Session stopped''${NC}"
    }

    cmd_status() {
        echo -e "''${GREEN}Active Sessions:''${NC}"
        if [[ -f "$SESSION_FILE" && -s "$SESSION_FILE" ]]; then
            while IFS='|' read -r path name timestamp; do
                local age=$(( ($(date +%s) - timestamp) / 60 ))
                echo -e "  ''${BLUE}$path''${NC}"
                echo -e "    Workspace: $name"
                echo -e "    Active for: ''${age} minutes"
            done < "$SESSION_FILE"
        else
            echo "  (no active sessions)"
        fi
    }

    cmd_list() {
        cmd_status
    }

    cmd_sync() {
        if [[ ! -d ".jj" ]]; then
            echo -e "''${RED}Error: Not in a jj repository''${NC}"
            exit 1
        fi

        echo -e "''${YELLOW}Syncing...''${NC}"
        jj git fetch --prune
        echo -e "''${GREEN}Sync complete''${NC}"
    }

    # Main
    COMMAND="''${1:-}"

    case "$COMMAND" in
        start)
            shift
            cmd_start "$@"
            ;;
        stop)
            cmd_stop
            ;;
        status|list)
            cmd_status
            ;;
        sync)
            cmd_sync
            ;;
        -h|--help|"")
            usage
            ;;
        *)
            echo -e "''${RED}Unknown command: $COMMAND''${NC}"
            usage
            ;;
    esac
  '';

  jjFastSyncContent = ''
    #!/usr/bin/env bash
    # jj-fast-sync: Sync repos with active sessions (5-minute interval)
    # Only syncs repos that have a .jj-autosync file with fast_sync=true
    set -euo pipefail

    SESSION_FILE="$HOME/.local/state/jj-autosync/active-sessions"
    LOG_FILE="/tmp/jj-fast-sync.log"
    CONFIG_FILE=".jj-autosync"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    }

    # Parse config file
    parse_config() {
        local config_file="$1"
        local key="$2"
        local default="$3"

        if [[ -f "$config_file" ]]; then
            local value=$(grep "^$key=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
            echo "''${value:-$default}"
        else
            echo "$default"
        fi
    }

    if [[ ! -f "$SESSION_FILE" || ! -s "$SESSION_FILE" ]]; then
        exit 0
    fi

    log "=== Fast sync starting ==="

    while IFS='|' read -r repo_path workspace_name timestamp; do
        if [[ -d "$repo_path/.jj" ]]; then
            # Find the repo root (workspace might be in a subdirectory)
            repo_root="$repo_path"
            while [[ "$repo_root" != "/" && ! -f "$repo_root/$CONFIG_FILE" ]]; do
                repo_root=$(dirname "$repo_root")
            done

            # Check config
            if [[ -f "$repo_root/$CONFIG_FILE" ]]; then
                fast_sync=$(parse_config "$repo_root/$CONFIG_FILE" "fast_sync" "false")
                if [[ "$fast_sync" == "true" ]]; then
                    log "Syncing: $repo_path ($workspace_name)"
                    cd "$repo_path"
                    jj git fetch 2>> "$LOG_FILE" || log "Fetch failed for $repo_path"
                else
                    log "Fast sync disabled for $repo_path, skipping"
                fi
            else
                log "No config file for $repo_path, skipping"
            fi
        fi
    done < "$SESSION_FILE"

    log "=== Fast sync complete ==="
  '';
in {
  config = mkIf enabled {
    # Install the scripts as executables
    home.packages = [
      (pkgs.writeShellScriptBin "jj-autosync" jjAutosyncContent)
      (pkgs.writeShellScriptBin "jj-workspace-session" jjWorkspaceSessionContent)
      (pkgs.writeShellScriptBin "jj-fast-sync" jjFastSyncContent)
    ];

    # launchd agents for macOS
    launchd.agents = mkIf isDarwin {
      # Hourly sync for all repos
      jj-autosync = {
        enable = true;
        config = {
          ProgramArguments = ["${pkgs.writeShellScript "jj-autosync" jjAutosyncContent}"];
          StartInterval = 3600; # 1 hour
          RunAtLoad = true;
          StandardOutPath = "/tmp/jj-autosync-launchd.log";
          StandardErrorPath = "/tmp/jj-autosync-launchd.err";
          EnvironmentVariables = {
            HOME = "/Users/${cfg.username or "monkey"}";
            PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin";
          };
        };
      };

      # Fast sync for active sessions (every 5 minutes)
      jj-fast-sync = {
        enable = true;
        config = {
          ProgramArguments = ["${pkgs.writeShellScript "jj-fast-sync" jjFastSyncContent}"];
          StartInterval = 300; # 5 minutes
          RunAtLoad = false; # Only runs when there are active sessions
          StandardOutPath = "/tmp/jj-fast-sync-launchd.log";
          StandardErrorPath = "/tmp/jj-fast-sync-launchd.err";
          EnvironmentVariables = {
            HOME = "/Users/${cfg.username or "monkey"}";
            PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin";
          };
        };
      };
    };

    # systemd user services for Linux
    systemd.user.services = mkIf (!isDarwin) {
      jj-autosync = {
        Unit = {
          Description = "jj repository auto-sync (hourly)";
          After = ["network-online.target"];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "jj-autosync" jjAutosyncContent}";
          Environment = [
            "HOME=%h"
            "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
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
            "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
          ];
        };
      };
    };

    systemd.user.timers = mkIf (!isDarwin) {
      jj-autosync = {
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
          Description = "5-minute jj fast sync timer";
        };
        Timer = {
          OnCalendar = "*:0/5"; # Every 5 minutes
          Persistent = true;
        };
        Install = {
          WantedBy = ["timers.target"];
        };
      };
    };
  };
}
