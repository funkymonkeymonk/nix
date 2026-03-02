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
    else pkgs.stdenv.isDarwin;

  # Configuration values with defaults
  reposDir = cfg.reposDir or "$HOME/repos";
  mainBranch = cfg.mainBranch or "main";
  hourlySync = cfg.hourlySync or true;
  fastSyncInterval = cfg.fastSyncInterval or 300;
  sessionTtlSeconds = cfg.sessionTtlSeconds or 1800; # 30 minutes default
  username = cfg.username or "";

  # Shared library content (embedded for Nix derivations)
  sharedLibContent = ''
    # Shared functions for jj-autosync scripts

    # Generate short unique id (4 hex chars) - portable, no xxd dependency
    generate_id() {
        od -An -tx1 -N4 /dev/urandom 2>/dev/null | tr -d ' \n' | head -c 4
    }

    # Parse a simple key=value config file
    parse_config() {
        local config_file="$1"
        local key="$2"
        local default="$3"

        if [[ -f "$config_file" ]]; then
            local value
            value=$(grep "^''${key}=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
            echo "''${value:-$default}"
        else
            echo "$default"
        fi
    }

    # Cross-platform notification
    notify() {
        local title="''${1:-Notification}"
        local message="''${2:-}"
        local urgency="''${3:-normal}"

        # Try noti first (cross-platform)
        if command -v noti &>/dev/null; then
            noti -t "$title" -m "$message" 2>/dev/null
            return
        fi

        # macOS fallbacks
        if [[ "$OSTYPE" == darwin* ]]; then
            if command -v terminal-notifier &>/dev/null; then
                terminal-notifier -title "$title" -message "$message" 2>/dev/null
            else
                osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
            fi
            return
        fi

        # Linux fallback
        if command -v notify-send &>/dev/null; then
            notify-send -u "$urgency" "$title" "$message" 2>/dev/null
            return
        fi
    }
  '';

  # Script content as strings
  jjAutosyncContent = ''
    #!/usr/bin/env bash
    # jj-autosync: Sync main branch with upstream
    # Runs as background service or on-demand
    # Only syncs repos that have a .jj-autosync file (opt-in per repo)
    set -euo pipefail

    # Embedded shared functions
    ${sharedLibContent}

    # Configuration from Nix options
    REPOS_DIR="''${JJ_AUTOSYNC_REPOS_DIR:-${reposDir}}"
    DEFAULT_MAIN_BRANCH="''${JJ_AUTOSYNC_MAIN_BRANCH:-${mainBranch}}"
    LOG_FILE="''${JJ_AUTOSYNC_LOG:-/tmp/jj-autosync.log}"
    CONFIG_FILE=".jj-autosync"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    }

    sync_repo() {
        local repo="$1"
        local repo_name
        repo_name=$(basename "$repo")

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
        local repo_enabled
        repo_enabled=$(parse_config "$CONFIG_FILE" "enabled" "true")
        local repo_main_branch
        repo_main_branch=$(parse_config "$CONFIG_FILE" "main" "$DEFAULT_MAIN_BRANCH")

        if [[ "$repo_enabled" != "true" ]]; then
            log "[$repo_name] Sync disabled in config, skipping"
            return 0
        fi

        log "[$repo_name] Starting sync (main=$repo_main_branch)..."

        # Fetch with prune
        if jj git fetch --prune 2>> "$LOG_FILE"; then
            log "[$repo_name] Fetch completed"
        else
            log "[$repo_name] Fetch failed"
            notify "jj-autosync" "Fetch failed for $repo_name" "critical"
            return 1
        fi

        # Update local main to match remote
        # First check if remote main exists
        local remote_main_exists
        if jj log -r "''${repo_main_branch}@origin" --no-graph -T 'commit_id' &>/dev/null; then
            remote_main_exists=true
        else
            remote_main_exists=false
        fi

        if [[ "$remote_main_exists" == "true" ]]; then
            # Ensure we're tracking the remote branch
            jj bookmark track "''${repo_main_branch}@origin" 2>> "$LOG_FILE" || true

            # Fast-forward local main to remote main
            # This moves the local bookmark to match the remote
            if jj bookmark set "$repo_main_branch" -r "''${repo_main_branch}@origin" 2>> "$LOG_FILE"; then
                log "[$repo_name] Updated $repo_main_branch to match origin"
            else
                log "[$repo_name] Could not update $repo_main_branch (may have local changes)"
            fi
        fi

        log "[$repo_name] Sync complete"
    }

    # Main execution
    log "=== jj-autosync starting ==="

    # Expand ~ and $HOME in repos dir
    REPOS_DIR="''${REPOS_DIR/#\~/$HOME}"
    REPOS_DIR="''${REPOS_DIR/\$HOME/$HOME}"

    # Find all jj repos in the repos directory that have opted in
    if [[ -d "$REPOS_DIR" ]]; then
        for repo in "$REPOS_DIR"/*/; do
            if [[ -d "$repo/.jj" && -f "$repo/$CONFIG_FILE" ]]; then
                sync_repo "$repo" || true
            fi
        done
    else
        log "Repos directory not found: $REPOS_DIR"
    fi

    log "=== jj-autosync complete ==="
  '';

  jjWorkspaceSessionContent = ''
    #!/usr/bin/env bash
    # jj-workspace-session: Manage workspace sessions with increased sync frequency
    # Delegates workspace creation to jj-workspace script
    set -euo pipefail

    # Embedded shared functions
    ${sharedLibContent}

    # Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    SESSION_DIR="''${HOME}/.local/state/jj-autosync"
    SESSION_FILE="$SESSION_DIR/active-sessions"
    LOCK_FILE="$SESSION_DIR/sessions.lock"
    SESSION_TTL_SECONDS="${toString sessionTtlSeconds}"

    mkdir -p "$SESSION_DIR"

    usage() {
        cat <<EOF
    Usage: jj-workspace-session <command> [args]

    Manage jj workspace sessions with fast sync (every ${toString (fastSyncInterval / 60)} minutes).
    Sessions auto-expire after ${toString (sessionTtlSeconds / 60)} minutes of inactivity.

    Commands:
      start [name] [base]    Start a session (creates workspace if name given)
      stop                   Stop session in current directory
      touch                  Reset session TTL (call periodically to keep alive)
      status                 Show active sessions
      list                   List active sessions
      sync                   Manually trigger sync for current repo
      prune                  Remove expired sessions

    Examples:
      jj-workspace-session start                    # Start session in current workspace
      jj-workspace-session start feat/auth          # Create workspace and start session
      jj-workspace-session start fix/bug develop    # Create workspace from develop
      jj-workspace-session touch                    # Keep session alive
      jj-workspace-session stop                     # Stop session
    EOF
        exit 1
    }

    # File locking for concurrent access safety
    acquire_lock() {
        local timeout=5
        local count=0
        while ! mkdir "$LOCK_FILE" 2>/dev/null; do
            sleep 0.1
            count=$((count + 1))
            if [[ $count -gt $((timeout * 10)) ]]; then
                echo -e "''${RED}Error: Could not acquire lock''${NC}" >&2
                return 1
            fi
        done
    }

    release_lock() {
        rmdir "$LOCK_FILE" 2>/dev/null || true
    }

    # Get current timestamp
    now() {
        date +%s
    }

    # Add or update a session
    # Format: repo_path|workspace_name|last_touch_timestamp
    add_session() {
        local repo_path="$1"
        local workspace_name="$2"

        acquire_lock
        trap release_lock EXIT

        # Remove existing entry for this path
        if [[ -f "$SESSION_FILE" ]]; then
            grep -v "^''${repo_path}|" "$SESSION_FILE" > "$SESSION_FILE.tmp" 2>/dev/null || true
            mv "$SESSION_FILE.tmp" "$SESSION_FILE"
        fi

        # Add new entry
        echo "''${repo_path}|''${workspace_name}|$(now)" >> "$SESSION_FILE"
    }

    # Touch (refresh TTL) for a session
    touch_session() {
        local repo_path="$1"

        acquire_lock
        trap release_lock EXIT

        if [[ ! -f "$SESSION_FILE" ]]; then
            return 1
        fi

        # Find and update the session
        local found=false
        local temp_file="$SESSION_FILE.tmp"
        > "$temp_file"

        while IFS='|' read -r path name timestamp; do
            if [[ "$path" == "$repo_path" ]]; then
                echo "''${path}|''${name}|$(now)" >> "$temp_file"
                found=true
            else
                echo "''${path}|''${name}|''${timestamp}" >> "$temp_file"
            fi
        done < "$SESSION_FILE"

        mv "$temp_file" "$SESSION_FILE"

        if [[ "$found" == "false" ]]; then
            return 1
        fi
    }

    remove_session() {
        local repo_path="$1"

        acquire_lock
        trap release_lock EXIT

        if [[ -f "$SESSION_FILE" ]]; then
            grep -v "^''${repo_path}|" "$SESSION_FILE" > "$SESSION_FILE.tmp" 2>/dev/null || true
            mv "$SESSION_FILE.tmp" "$SESSION_FILE"
        fi
    }

    is_session_active() {
        local repo_path="$1"
        if [[ -f "$SESSION_FILE" ]]; then
            grep -q "^''${repo_path}|" "$SESSION_FILE"
            return $?
        fi
        return 1
    }

    # Prune expired sessions (TTL exceeded)
    prune_expired() {
        acquire_lock
        trap release_lock EXIT

        if [[ ! -f "$SESSION_FILE" ]]; then
            return 0
        fi

        local current_time
        current_time=$(now)
        local temp_file="$SESSION_FILE.tmp"
        local pruned=0
        > "$temp_file"

        while IFS='|' read -r path name timestamp; do
            local age=$((current_time - timestamp))
            if [[ $age -lt $SESSION_TTL_SECONDS ]]; then
                echo "''${path}|''${name}|''${timestamp}" >> "$temp_file"
            else
                echo "Pruned expired session: $path ($name) - inactive for $((age / 60)) minutes" >&2
                pruned=$((pruned + 1))
            fi
        done < "$SESSION_FILE"

        mv "$temp_file" "$SESSION_FILE"
        echo "$pruned"
    }

    cmd_start() {
        local name="''${1:-}"
        local base="''${2:-main}"

        # Ensure we're in a jj repo
        if [[ ! -d ".jj" ]]; then
            echo -e "''${RED}Error: Not in a jj repository''${NC}"
            exit 1
        fi

        local repo_path
        repo_path=$(pwd)
        local workspace_name="default"

        # If name provided, create a workspace using jj-workspace
        if [[ -n "$name" ]]; then
            echo -e "''${GREEN}Creating workspace via jj-workspace...''${NC}"

            # Call jj-workspace create and capture output
            local output
            if ! output=$(jj-workspace create "$name" "$base" 2>&1); then
                echo -e "''${RED}Failed to create workspace:''${NC}"
                echo "$output"
                exit 1
            fi

            echo "$output"

            # Parse the workspace path from output (last line: WORKSPACE_PATH=...)
            local ws_path
            ws_path=$(echo "$output" | grep "^WORKSPACE_PATH=" | cut -d'=' -f2)

            if [[ -n "$ws_path" && -d "$ws_path" ]]; then
                repo_path=$(cd "$ws_path" && pwd)
                # Extract workspace name from path
                workspace_name=$(basename "$ws_path")
            fi
        fi

        # Register the session
        add_session "$repo_path" "$workspace_name"

        echo -e "''${GREEN}Session started with ${toString (fastSyncInterval / 60)}-minute sync interval''${NC}"
        echo -e "Session TTL: ${toString (sessionTtlSeconds / 60)} minutes (auto-refreshed on sync)"
        echo -e "Run 'jj-workspace-session stop' when done"
    }

    cmd_stop() {
        local repo_path
        repo_path=$(pwd)

        if ! is_session_active "$repo_path"; then
            echo -e "''${YELLOW}No active session in current directory''${NC}"
            return 0
        fi

        remove_session "$repo_path"
        echo -e "''${GREEN}Session stopped''${NC}"
    }

    cmd_touch() {
        local repo_path
        repo_path=$(pwd)

        if touch_session "$repo_path"; then
            echo -e "''${GREEN}Session TTL refreshed''${NC}"
        else
            echo -e "''${YELLOW}No active session in current directory''${NC}"
            return 1
        fi
    }

    cmd_status() {
        # Prune expired first
        local pruned
        pruned=$(prune_expired 2>&1 | tail -1)
        if [[ "$pruned" -gt 0 ]]; then
            echo -e "''${YELLOW}Pruned $pruned expired session(s)''${NC}"
            echo ""
        fi

        echo -e "''${GREEN}Active Sessions:''${NC}"
        if [[ -f "$SESSION_FILE" && -s "$SESSION_FILE" ]]; then
            local current_time
            current_time=$(now)
            while IFS='|' read -r path name timestamp; do
                local age=$((current_time - timestamp))
                local remaining=$((SESSION_TTL_SECONDS - age))
                echo -e "  ''${BLUE}$path''${NC}"
                echo -e "    Workspace: $name"
                echo -e "    Last activity: $((age / 60)) min ago"
                echo -e "    Expires in: $((remaining / 60)) min"
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

        # Touch the session to refresh TTL
        local repo_path
        repo_path=$(pwd)
        touch_session "$repo_path" 2>/dev/null || true

        echo -e "''${YELLOW}Syncing...''${NC}"
        if jj git fetch --prune; then
            echo -e "''${GREEN}Sync complete''${NC}"
        else
            echo -e "''${RED}Sync failed''${NC}"
            exit 1
        fi
    }

    cmd_prune() {
        local pruned
        pruned=$(prune_expired 2>&1 | tail -1)
        echo -e "''${GREEN}Pruned $pruned expired session(s)''${NC}"
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
        touch)
            cmd_touch
            ;;
        status|list)
            cmd_status
            ;;
        sync)
            cmd_sync
            ;;
        prune)
            cmd_prune
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
    # jj-fast-sync: Sync repos with active sessions
    # Only syncs repos that have a .jj-autosync file with fast_sync=true
    # Prunes expired sessions and refreshes TTL on successful sync
    set -euo pipefail

    # Embedded shared functions
    ${sharedLibContent}

    SESSION_DIR="$HOME/.local/state/jj-autosync"
    SESSION_FILE="$SESSION_DIR/active-sessions"
    LOCK_FILE="$SESSION_DIR/sessions.lock"
    LOG_FILE="/tmp/jj-fast-sync.log"
    CONFIG_FILE=".jj-autosync"
    SESSION_TTL_SECONDS="${toString sessionTtlSeconds}"

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    }

    now() {
        date +%s
    }

    # File locking
    acquire_lock() {
        local timeout=5
        local count=0
        while ! mkdir "$LOCK_FILE" 2>/dev/null; do
            sleep 0.1
            count=$((count + 1))
            if [[ $count -gt $((timeout * 10)) ]]; then
                log "Could not acquire lock"
                exit 1
            fi
        done
    }

    release_lock() {
        rmdir "$LOCK_FILE" 2>/dev/null || true
    }

    # Prune expired sessions and return active ones
    prune_and_get_sessions() {
        acquire_lock
        trap release_lock EXIT

        if [[ ! -f "$SESSION_FILE" ]]; then
            return
        fi

        local current_time
        current_time=$(now)
        local temp_file="$SESSION_FILE.tmp"
        > "$temp_file"

        while IFS='|' read -r path name timestamp; do
            local age=$((current_time - timestamp))
            if [[ $age -lt $SESSION_TTL_SECONDS ]]; then
                echo "''${path}|''${name}|''${timestamp}" >> "$temp_file"
                echo "''${path}|''${name}|''${timestamp}"
            else
                log "Pruned expired session: $path ($name)"
            fi
        done < "$SESSION_FILE"

        mv "$temp_file" "$SESSION_FILE"
    }

    # Update session timestamp after successful sync
    touch_session() {
        local target_path="$1"

        acquire_lock
        trap release_lock EXIT

        if [[ ! -f "$SESSION_FILE" ]]; then
            return
        fi

        local temp_file="$SESSION_FILE.tmp"
        > "$temp_file"

        while IFS='|' read -r path name timestamp; do
            if [[ "$path" == "$target_path" ]]; then
                echo "''${path}|''${name}|$(now)" >> "$temp_file"
            else
                echo "''${path}|''${name}|''${timestamp}" >> "$temp_file"
            fi
        done < "$SESSION_FILE"

        mv "$temp_file" "$SESSION_FILE"
    }

    # No active sessions? Exit early
    if [[ ! -f "$SESSION_FILE" || ! -s "$SESSION_FILE" ]]; then
        exit 0
    fi

    log "=== Fast sync starting ==="

    # Get active sessions (also prunes expired ones)
    sessions=$(prune_and_get_sessions)

    if [[ -z "$sessions" ]]; then
        log "No active sessions after pruning"
        exit 0
    fi

    # Process each active session
    echo "$sessions" | while IFS='|' read -r repo_path workspace_name timestamp; do
        if [[ -z "$repo_path" ]]; then
            continue
        fi

        # Find the repo root (workspace might be in a subdirectory)
        repo_root="$repo_path"
        while [[ "$repo_root" != "/" && ! -d "$repo_root/.jj" ]]; do
            repo_root=$(dirname "$repo_root")
        done

        # Verify it's a jj repo
        if [[ ! -d "$repo_root/.jj" ]]; then
            log "Not a jj repo: $repo_path, skipping"
            continue
        fi

        # Check config at repo root level
        local config_path="$repo_root/$CONFIG_FILE"
        if [[ ! -f "$config_path" ]]; then
            # Also check workspace path
            config_path="$repo_path/$CONFIG_FILE"
        fi

        if [[ -f "$config_path" ]]; then
            local fast_sync
            fast_sync=$(parse_config "$config_path" "fast_sync" "false")
            if [[ "$fast_sync" == "true" ]]; then
                log "Syncing: $repo_path ($workspace_name)"
                if (cd "$repo_path" && jj git fetch --prune 2>> "$LOG_FILE"); then
                    log "Sync successful for $repo_path"
                    # Refresh TTL on successful sync
                    touch_session "$repo_path"
                else
                    log "Fetch failed for $repo_path"
                    notify "jj-fast-sync" "Sync failed for $(basename "$repo_path")" "critical"
                fi
            else
                log "Fast sync disabled for $repo_path, skipping"
            fi
        else
            log "No config file for $repo_path, skipping"
        fi
    done

    log "=== Fast sync complete ==="
  '';

  jjAutosyncStatusContent = ''
    #!/usr/bin/env bash
    # jj-autosync-status: Show status and logs for jj-autosync services
    set -euo pipefail

    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    echo -e "''${GREEN}=== jj-autosync Status ===''${NC}"
    echo ""

    # Show session status
    echo -e "''${BLUE}Active Sessions:''${NC}"
    jj-workspace-session status 2>/dev/null || echo "  (session manager not available)"
    echo ""

    # Show recent logs
    echo -e "''${BLUE}Recent Hourly Sync Log:''${NC}"
    if [[ -f /tmp/jj-autosync.log ]]; then
        tail -20 /tmp/jj-autosync.log
    else
        echo "  (no log file)"
    fi
    echo ""

    echo -e "''${BLUE}Recent Fast Sync Log:''${NC}"
    if [[ -f /tmp/jj-fast-sync.log ]]; then
        tail -20 /tmp/jj-fast-sync.log
    else
        echo "  (no log file)"
    fi
  '';

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
