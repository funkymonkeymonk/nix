#!/usr/bin/env bash
# yak-claim.sh - Safely claim a yak following the claim protocol
#
# Performs: sync → check state → start → sync
# Exits non-zero if yak is already wip or done.
#
# Usage:
#   ./yak-claim.sh "yak name"
#
# Exit codes:
#   0 - claimed successfully
#   1 - yak already wip or done (skip it)
#   2 - yak not found

set -euo pipefail

YAK_NAME="${1:-}"
if [[ -z "$YAK_NAME" ]]; then
    echo "Usage: $0 \"yak name\"" >&2
    exit 2
fi

echo "Syncing yaks..." >&2
yx sync

# Check current state
state=$(yx show "$YAK_NAME" --format json 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('state','unknown'))" \
    || echo "unknown")

case "$state" in
    todo)
        echo "Claiming: $YAK_NAME" >&2
        yx start "$YAK_NAME"
        yx sync
        echo "Claimed." >&2
        exit 0
        ;;
    wip)
        echo "Already in progress: $YAK_NAME — skipping" >&2
        exit 1
        ;;
    done)
        echo "Already done: $YAK_NAME — skipping" >&2
        exit 1
        ;;
    *)
        echo "Unknown state '$state' for: $YAK_NAME" >&2
        exit 2
        ;;
esac
