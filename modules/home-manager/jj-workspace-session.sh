#!/usr/bin/env bash
# jj-workspace-session: Manage workspace sessions with increased sync frequency
# Delegates workspace creation to jj-workspace script
set -euo pipefail

# Shared functions (inlined from jj-autosync-lib.sh via builtins.readFile)
# @SHARED_LIB@

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SESSION_DIR="${HOME}/.local/state/jj-autosync"
SESSION_FILE="$SESSION_DIR/active-sessions"
LOCK_FILE="$SESSION_DIR/sessions.lock"
SESSION_TTL_SECONDS="${JJ_AUTOSYNC_SESSION_TTL:-1800}"
FAST_SYNC_INTERVAL="${JJ_AUTOSYNC_FAST_SYNC_INTERVAL:-300}"

mkdir -p "$SESSION_DIR"

usage() {
    local fast_sync_minutes=$(( FAST_SYNC_INTERVAL / 60 ))
    local ttl_minutes=$(( SESSION_TTL_SECONDS / 60 ))
    cat <<EOF
Usage: jj-workspace-session <command> [args]

Manage jj workspace sessions with fast sync (every ${fast_sync_minutes} minutes).
Sessions auto-expire after ${ttl_minutes} minutes of inactivity.

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
            echo -e "${RED}Error: Could not acquire lock${NC}" >&2
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
        grep -v "^${repo_path}|" "$SESSION_FILE" > "$SESSION_FILE.tmp" 2>/dev/null || true
        mv "$SESSION_FILE.tmp" "$SESSION_FILE"
    fi

    # Add new entry
    echo "${repo_path}|${workspace_name}|$(now)" >> "$SESSION_FILE"
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
    true > "$temp_file"

    while IFS='|' read -r path name timestamp; do
        if [[ "$path" == "$repo_path" ]]; then
            echo "${path}|${name}|$(now)" >> "$temp_file"
            found=true
        else
            echo "${path}|${name}|${timestamp}" >> "$temp_file"
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
        grep -v "^${repo_path}|" "$SESSION_FILE" > "$SESSION_FILE.tmp" 2>/dev/null || true
        mv "$SESSION_FILE.tmp" "$SESSION_FILE"
    fi
}

is_session_active() {
    local repo_path="$1"
    if [[ -f "$SESSION_FILE" ]]; then
        grep -q "^${repo_path}|" "$SESSION_FILE"
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
    true > "$temp_file"

    while IFS='|' read -r path name timestamp; do
        local age=$((current_time - timestamp))
        if [[ $age -lt $SESSION_TTL_SECONDS ]]; then
            echo "${path}|${name}|${timestamp}" >> "$temp_file"
        else
            echo "Pruned expired session: $path ($name) - inactive for $((age / 60)) minutes" >&2
            pruned=$((pruned + 1))
        fi
    done < "$SESSION_FILE"

    mv "$temp_file" "$SESSION_FILE"
    echo "$pruned"
}

cmd_start() {
    local name="${1:-}"
    local base="${2:-main}"

    # Ensure we're in a jj repo
    if [[ ! -d ".jj" ]]; then
        echo -e "${RED}Error: Not in a jj repository${NC}"
        exit 1
    fi

    local repo_path
    repo_path=$(pwd)
    local workspace_name="default"

    # If name provided, create a workspace using jj-workspace
    if [[ -n "$name" ]]; then
        echo -e "${GREEN}Creating workspace via jj-workspace...${NC}"

        # Call jj-workspace create and capture output
        local output
        if ! output=$(jj-workspace create "$name" "$base" 2>&1); then
            echo -e "${RED}Failed to create workspace:${NC}"
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

    local fast_sync_minutes=$(( FAST_SYNC_INTERVAL / 60 ))
    local ttl_minutes=$(( SESSION_TTL_SECONDS / 60 ))
    echo -e "${GREEN}Session started with ${fast_sync_minutes}-minute sync interval${NC}"
    echo -e "Session TTL: ${ttl_minutes} minutes (auto-refreshed on sync)"
    echo -e "Run 'jj-workspace-session stop' when done"
}

cmd_stop() {
    local repo_path
    repo_path=$(pwd)

    if ! is_session_active "$repo_path"; then
        echo -e "${YELLOW}No active session in current directory${NC}"
        return 0
    fi

    remove_session "$repo_path"
    echo -e "${GREEN}Session stopped${NC}"
}

cmd_touch() {
    local repo_path
    repo_path=$(pwd)

    if touch_session "$repo_path"; then
        echo -e "${GREEN}Session TTL refreshed${NC}"
    else
        echo -e "${YELLOW}No active session in current directory${NC}"
        return 1
    fi
}

cmd_status() {
    # Prune expired first
    local pruned
    pruned=$(prune_expired 2>&1 | tail -1)
    if [[ "$pruned" -gt 0 ]]; then
        echo -e "${YELLOW}Pruned $pruned expired session(s)${NC}"
        echo ""
    fi

    echo -e "${GREEN}Active Sessions:${NC}"
    if [[ -f "$SESSION_FILE" && -s "$SESSION_FILE" ]]; then
        local current_time
        current_time=$(now)
        while IFS='|' read -r path name timestamp; do
            local age=$((current_time - timestamp))
            local remaining=$((SESSION_TTL_SECONDS - age))
            echo -e "  ${BLUE}$path${NC}"
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
        echo -e "${RED}Error: Not in a jj repository${NC}"
        exit 1
    fi

    # Touch the session to refresh TTL
    local repo_path
    repo_path=$(pwd)
    touch_session "$repo_path" 2>/dev/null || true

    echo -e "${YELLOW}Syncing...${NC}"
    if jj git fetch --prune; then
        echo -e "${GREEN}Sync complete${NC}"
    else
        echo -e "${RED}Sync failed${NC}"
        exit 1
    fi
}

cmd_prune() {
    local pruned
    pruned=$(prune_expired 2>&1 | tail -1)
    echo -e "${GREEN}Pruned $pruned expired session(s)${NC}"
}

# Main
COMMAND="${1:-}"

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
    status | list)
        cmd_status
        ;;
    sync)
        cmd_sync
        ;;
    prune)
        cmd_prune
        ;;
    -h | --help | "")
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        usage
        ;;
esac
