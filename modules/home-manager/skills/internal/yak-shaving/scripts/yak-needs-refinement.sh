#!/usr/bin/env bash
# yak-needs-refinement.sh - Check if a yak has enough context to implement autonomously
#
# A yak needs refinement if it lacks:
#   - Any context (no Goal, no Acceptance Criteria)
#   - Specific file paths to work on
#   - Clear acceptance criteria (no checkboxes or vague ones)
#
# Usage:
#   ./yak-needs-refinement.sh "yak name"
#
# Exit codes:
#   0 - yak is clear enough to implement
#   1 - yak needs refinement
#
# Outputs:
#   If needs refinement: prints reason to stdout
#   If clear: prints nothing

set -euo pipefail

YAK_NAME="${1:-}"
if [[ -z "$YAK_NAME" ]]; then
    echo "Usage: $0 \"yak name\"" >&2
    exit 2
fi

# Get yak details
yak_json=$(yx show "$YAK_NAME" --format json 2>/dev/null) || {
    echo "Yak not found: $YAK_NAME" >&2
    exit 2
}

context=$(echo "$yak_json" | python3 -c "import json,sys; y=json.load(sys.stdin); v=y.get('context'); print('' if v is None else v)")
name=$(echo "$yak_json" | python3 -c "import json,sys; y=json.load(sys.stdin); print(y.get('name',''))")

# Check 1: Has any context at all?
if [[ -z "$context" || "$context" == "null" ]]; then
    echo "No context defined. Need: Goal, Acceptance Criteria, and key files."
    exit 1
fi

# Check 2: Has acceptance criteria (looks for checkboxes or numbered criteria)
if ! echo "$context" | grep -qiE '(- \[|acceptance criteria|criteria|definition of done)'; then
    echo "No acceptance criteria found. Context exists but lacks testable criteria."
    exit 1
fi

# Check 3: Mentions specific files (heuristic: any path-like string — slash-separated or filename with extension)
if ! echo "$context" | grep -qE '([a-zA-Z0-9_-]+/[a-zA-Z0-9_./-]+|[a-zA-Z0-9_-]+\.[a-zA-Z]{1,6})'; then
    echo "No specific files mentioned. Need concrete file paths for autonomous implementation."
    exit 1
fi

# Yak is clear enough
exit 0
