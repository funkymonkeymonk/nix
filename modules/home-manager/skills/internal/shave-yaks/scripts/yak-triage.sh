#!/usr/bin/env bash
# yak-triage.sh - Find actionable yaks ready for implementation
#
# Outputs one yak per line (JSON objects) that:
#   - Are in state "todo"
#   - Have no children of their own (leaf nodes)
#   - Are not tagged with any blocking tag (e.g. @needs-human, @needs-e2e-vm)
#   - Are not already wip (claimed by another agent)
#   - Do not have a non-empty "## Blocked By" section in their context markdown
#
# Context is parsed directly from the JSON returned by `yx ls --format json`;
# no extra `yx context` calls are needed. A yak is considered semantically
# blocked if its context contains "## Blocked By" followed by non-whitespace
# content on the next line.
#
# Usage:
#   ./yak-triage.sh                   # Print actionable yaks as JSON array
#   ./yak-triage.sh --names           # Print just the names, one per line
#   ./yak-triage.sh --count           # Print count only
#   ./yak-triage.sh --max N           # Limit output to N yaks (default: unlimited)
#   ./yak-triage.sh --include-blocked # Include yaks blocked by "## Blocked By" (debug)
#
# Exit codes:
#   0 - found actionable yaks
#   1 - no actionable yaks found

set -euo pipefail

# Parse args
MODE="json"
MAX=0
INCLUDE_BLOCKED=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --names)           MODE="names" ;;
        --count)           MODE="count" ;;
        --max)             MAX="$2"; shift ;;
        --include-blocked) INCLUDE_BLOCKED=true ;;
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

# Filter to actionable leaf yaks using Python (available everywhere).
# Also filters out semantically blocked yaks (## Blocked By in context)
# unless INCLUDE_BLOCKED is "true".
actionable=$(python3 - "$all_yaks" "$INCLUDE_BLOCKED" "${BLOCKING_TAGS[@]}" <<'PYEOF'
import json, sys, re

raw = sys.argv[1]
include_blocked = sys.argv[2].lower() == "true"
blocking_tags = set(sys.argv[3:])

yaks = json.loads(raw)

def has_blocked_by(context):
    """Return True if context has a non-empty '## Blocked By' section."""
    if not context:
        return False
    lines = context.splitlines()
    for i, line in enumerate(lines):
        if re.match(r'^## Blocked By\s*$', line, re.IGNORECASE):
            # Look at the next non-empty line
            for j in range(i + 1, len(lines)):
                next_line = lines[j].strip()
                if next_line and not next_line.startswith("#"):
                    return True
                elif next_line.startswith("##"):
                    # Hit the next section header with no content
                    break
    return False

def is_actionable(yak, include_blocked):
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
    # Must not have a non-empty "## Blocked By" section in context
    if not include_blocked and has_blocked_by(yak.get("context")):
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
actionable = [y for y in flat if is_actionable(y, include_blocked)]
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
