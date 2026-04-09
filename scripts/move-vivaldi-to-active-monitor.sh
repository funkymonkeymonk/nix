#!/usr/bin/env bash

# Move all Vivaldi windows to the currently focused monitor
# When monitor focus changes, Vivaldi will "follow" to the active monitor
# while maintaining its workspace assignment

set -euo pipefail

# Vivaldi app bundle ID
VIVALDI_APP_ID="com.vivaldi.Vivaldi"

# Get the name of the currently focused monitor
FOCUSED_MONITOR=$(aerospace list-monitors --focused --format '{monitor-name}' | tr -d '[:space:]')

if [ -z "$FOCUSED_MONITOR" ]; then
    echo "move-vivaldi: No focused monitor found" >&2
    exit 0
fi

# Get all Vivaldi window IDs
VIVALDI_WINDOWS=$(aerospace list-windows --app-bundle-id "$VIVALDI_APP_ID" --format '{window-id}' 2>/dev/null || true)

# Exit gracefully if no Vivaldi windows
if [ -z "$VIVALDI_WINDOWS" ]; then
    exit 0
fi

# Save current focus to restore later
ORIGINAL_FOCUS=$(aerospace list-windows --focused --format '{window-id}' 2>/dev/null || true)

# Track which windows we moved for logging
MOVED_WINDOWS=()

# Move each Vivaldi window to the focused monitor
while IFS= read -r window_id; do
    if [ -z "$window_id" ]; then
        continue
    fi
    
    # Check if window is already on this monitor
    CURRENT_MONITOR=$(aerospace list-windows --window-id "$window_id" --format '{monitor-name}' 2>/dev/null | tr -d '[:space:]')
    
    if [ "$CURRENT_MONITOR" != "$FOCUSED_MONITOR" ]; then
        # Move window to focused monitor (preserves workspace)
        aerospace move-node-to-monitor --window-id "$window_id" "$FOCUSED_MONITOR" 2>/dev/null || true
        MOVED_WINDOWS+=("$window_id")
    fi
done <<< "$VIVALDI_WINDOWS"

# Restore original focus if we had one
if [ -n "$ORIGINAL_FOCUS" ]; then
    # Small delay to ensure move operations complete
    sleep 0.1
    aerospace focus --window-id "$ORIGINAL_FOCUS" 2>/dev/null || true
fi

# Log movement (optional, can be removed in production)
if [ ${#MOVED_WINDOWS[@]} -gt 0 ]; then
    echo "move-vivaldi: Moved ${#MOVED_WINDOWS[@]} Vivaldi window(s) to $FOCUSED_MONITOR" >&2
fi

exit 0
