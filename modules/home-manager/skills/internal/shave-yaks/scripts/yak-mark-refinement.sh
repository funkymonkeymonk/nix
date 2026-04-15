#!/usr/bin/env bash
# yak-mark-refinement.sh - Tag a yak as needing human refinement
#
# Tags the yak with @needs-human and appends a refinement request to context.
#
# Usage:
#   ./yak-mark-refinement.sh "yak name" "reason why it needs refinement"

set -euo pipefail

YAK_NAME="${1:-}"
REASON="${2:-Insufficient context for autonomous implementation.}"

if [[ -z "$YAK_NAME" ]]; then
    echo "Usage: $0 \"yak name\" \"reason\"" >&2
    exit 1
fi

echo "Marking '$YAK_NAME' as needing refinement..." >&2

# Tag it
yx tag "$YAK_NAME" @needs-human

# Get existing context and append refinement note
existing=$(yx context --show "$YAK_NAME" 2>/dev/null || echo "")

{
    if [[ -n "$existing" ]]; then
        echo "$existing"
        echo ""
    fi
    echo "## Needs Refinement"
    echo ""
    echo "Flagged by autonomous agent on $(date '+%Y-%m-%d')."
    echo ""
    echo "**Reason:** $REASON"
    echo ""
    echo "To unblock: add Goal, Acceptance Criteria with checkboxes, and specific file paths."
} | yx context "$YAK_NAME"

yx sync
echo "Tagged '$YAK_NAME' with @needs-human. Reason: $REASON" >&2
