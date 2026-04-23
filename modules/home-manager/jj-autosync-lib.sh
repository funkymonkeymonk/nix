#!/usr/bin/env bash
# jj-autosync-lib: Shared functions for jj-autosync scripts
# Source this file in other scripts: source "$(dirname "$0")/jj-autosync-lib.sh"
# Note: when used via Nix builtins.readFile, inline into the consuming script

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
        value=$(grep "^${key}=" "$config_file" 2>/dev/null | cut -d'=' -f2- | tr -d ' ')
        echo "${value:-$default}"
    else
        echo "$default"
    fi
}

# Cross-platform notification
notify() {
    local title="${1:-Notification}"
    local message="${2:-}"
    local urgency="${3:-normal}"

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
