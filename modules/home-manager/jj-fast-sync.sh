#!/usr/bin/env bash
# jj-fast-sync: Sync repos with active sessions
# Only syncs repos that have a .jj-autosync file with fast_sync=true
# Prunes expired sessions and refreshes TTL on successful sync
set -euo pipefail

# Shared functions (inlined from jj-autosync-lib.sh via builtins.readFile)
# @SHARED_LIB@

SESSION_DIR="$HOME/.local/state/jj-autosync"
SESSION_FILE="$SESSION_DIR/active-sessions"
LOCK_FILE="$SESSION_DIR/sessions.lock"
LOG_FILE="/tmp/jj-fast-sync.log"
CONFIG_FILE=".jj-autosync"
SESSION_TTL_SECONDS="${JJ_AUTOSYNC_SESSION_TTL:-1800}"

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
    true > "$temp_file"

    while IFS='|' read -r path name timestamp; do
        local age=$((current_time - timestamp))
        if [[ $age -lt $SESSION_TTL_SECONDS ]]; then
            echo "${path}|${name}|${timestamp}" >> "$temp_file"
            echo "${path}|${name}|${timestamp}"
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
    true > "$temp_file"

    while IFS='|' read -r path name timestamp; do
        if [[ "$path" == "$target_path" ]]; then
            echo "${path}|${name}|$(now)" >> "$temp_file"
        else
            echo "${path}|${name}|${timestamp}" >> "$temp_file"
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
echo "$sessions" | while IFS='|' read -r repo_path workspace_name _timestamp; do
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
    config_path="$repo_root/$CONFIG_FILE"
    if [[ ! -f "$config_path" ]]; then
        # Also check workspace path
        config_path="$repo_path/$CONFIG_FILE"
    fi

    if [[ -f "$config_path" ]]; then
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
