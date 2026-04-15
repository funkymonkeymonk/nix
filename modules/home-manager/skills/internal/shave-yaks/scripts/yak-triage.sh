#!/usr/bin/env bash
# yak-triage.sh - Find actionable yaks ready for implementation
#
# Outputs one yak per line (JSON objects) that:
#   - Are in state "todo"
#   - Have no children of their own (leaf nodes)
#   - Are not tagged with any blocking tag (e.g. @needs-human, @needs-e2e-vm)
#   - Are not already wip (claimed by another agent)
#
# Usage:
#   ./yak-triage.sh                  # Print actionable yaks as JSON array
#   ./yak-triage.sh --names          # Print just the names, one per line
#   ./yak-triage.sh --count          # Print count only
#   ./yak-triage.sh --max N          # Limit output to N yaks (default: unlimited)
#
# Exit codes:
#   0 - found actionable yaks
#   1 - no actionable yaks found

set -euo pipefail

# Parse args
MODE="json"
MAX=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --names) MODE="names" ;;
        --count) MODE="count" ;;
        --max)   MAX="$2"; shift ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
    shift
done

# Blocking tags - yaks with these should not be auto-implemented
BLOCKING_TAGS=(
    "@needs-human"
    "@needs-e2e-vm"
    "@needs-refactoring"
    "@blocked"
    "@wip"
)

# Get all yaks as flat JSON
all_yaks=$(yx ls --format json 2>/dev/null)

# Filter to actionable leaf yaks using Python (available everywhere)
actionable=$(python3 - "$all_yaks" "${BLOCKING_TAGS[@]}" <<'PYEOF'
import json, sys

raw = sys.argv[1]
blocking_tags = set(sys.argv[2:])

yaks = json.loads(raw)

def is_actionable(yak):
    # Must be todo state
    if yak.get("state") != "todo":
        return False
    # Must be a leaf (no children, or all children are done)
    children = yak.get("children", [])
    if children:
        non_done = [c for c in children if c.get("state") != "done"]
        if non_done:
            return False
    # Must not have blocking tags
    tags = set(yak.get("tags", []))
    if tags & blocking_tags:
        return False
    return True

def flatten(yaks):
    """Recursively flatten yak tree into list."""
    result = []
    for y in yaks:
        result.append(y)
        for child in y.get("children", []):
            result.append(child)
            for grandchild in child.get("children", []):
                result.append(grandchild)
    return result

flat = flatten(yaks)
actionable = [y for y in flat if is_actionable(y)]
print(json.dumps(actionable, indent=2))
PYEOF
)

count=$(echo "$actionable" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

if [[ "$count" -eq 0 ]]; then
    if [[ "$MODE" == "count" ]]; then
        echo "0"
    fi
    exit 1
fi

# Apply max limit if set
if [[ "$MAX" -gt 0 ]]; then
    actionable=$(echo "$actionable" | python3 -c "
import json, sys
yaks = json.load(sys.stdin)
print(json.dumps(yaks[:$MAX], indent=2))
")
    count=$(echo "$actionable" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
fi

case "$MODE" in
    json)
        echo "$actionable"
        ;;
    names)
        echo "$actionable" | python3 -c "
import json, sys
for y in json.load(sys.stdin):
    print(y['name'])
"
        ;;
    count)
        echo "$count"
        ;;
esac
