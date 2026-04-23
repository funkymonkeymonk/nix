#!/usr/bin/env bash
# jj-autosync: Sync main branch with upstream
# Runs as background service or on-demand
# Only syncs repos that have a .jj-autosync file (opt-in per repo)
set -euo pipefail

# Shared functions (inlined from jj-autosync-lib.sh via builtins.readFile)
# @SHARED_LIB@

# Configuration from environment (set by launchd/systemd or defaults)
REPOS_DIR="${JJ_AUTOSYNC_REPOS_DIR:-$HOME/repos}"
DEFAULT_MAIN_BRANCH="${JJ_AUTOSYNC_MAIN_BRANCH:-main}"
LOG_FILE="${JJ_AUTOSYNC_LOG:-/tmp/jj-autosync.log}"
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
    if jj log -r "${repo_main_branch}@origin" --no-graph -T 'commit_id' &>/dev/null; then
        remote_main_exists=true
    else
        remote_main_exists=false
    fi

    if [[ "$remote_main_exists" == "true" ]]; then
        # Ensure we're tracking the remote branch
        jj bookmark track "${repo_main_branch}@origin" 2>> "$LOG_FILE" || true

        # Fast-forward local main to remote main
        # This moves the local bookmark to match the remote
        if jj bookmark set "$repo_main_branch" -r "${repo_main_branch}@origin" 2>> "$LOG_FILE"; then
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
REPOS_DIR="${REPOS_DIR/#\~/$HOME}"
REPOS_DIR="${REPOS_DIR/\$HOME/$HOME}"

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
