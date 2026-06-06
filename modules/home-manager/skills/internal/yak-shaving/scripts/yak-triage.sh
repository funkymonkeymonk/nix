#!/usr/bin/env bash
# yak-triage.sh - Find actionable yaks ready for implementation
#
# Outputs one yak per line (JSON objects) that:
#   - Are in state "todo"
#   - Have no children of their own (leaf nodes)
#   - Are not tagged with any blocking tag (e.g. @needs-human, @blocked, @wip)
#   - Are not already wip (claimed by another agent)
#   - Do not have unmet prerequisites in their "## Prerequisites" section
#   - Do not have a non-empty "## Blocked By" section in context
#
# Dependencies are resolved via the "## Prerequisites" section in each yak's
# context. A yak with prerequisites where at least one is not "done" is treated
# as blocked. This means @blocked tags are informational for humans -- triage
# always resolves the dependency graph from context.
#
# Usage:
#   ./yak-triage.sh                   # Print actionable yaks as JSON array
#   ./yak-triage.sh --names           # Print just the names, one per line
#   ./yak-triage.sh --count           # Print count only
#   ./yak-triage.sh --max N           # Limit output to N yaks (default: unlimited)
#   ./yak-triage.sh --include-blocked # Include blocked yaks (debug)
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

# Filter to actionable leaf yaks using Python.
# Resolves ## Prerequisites and ## Blocked By sections in context.
actionable=$(python3 - "$all_yaks" "$INCLUDE_BLOCKED" "${BLOCKING_TAGS[@]}" <<'PYEOF'
import json, sys, re

raw = sys.argv[1]
include_blocked = sys.argv[2].lower() == "true"
blocking_tags = set(sys.argv[3:])

yaks = json.loads(raw)

def flatten(items):
    """Recursively flatten yak tree into list (arbitrary depth)."""
    result = []
    for item in items:
        result.append(item)
        for child in item.get("children", []):
            result.append(child)
            result.extend(flatten(child.get("children", [])))
    return result

def build_name_state_map(flat_yaks):
    """Build name -> state lookup from flat yak list."""
    return {y["name"]: y.get("state", "todo") for y in flat_yaks}

def parse_section_items(context, section_name):
    """Extract list items from a named ## Section in context."""
    if not context:
        return []
    lines = context.splitlines()
    items = []
    in_section = False
    for line in lines:
        if re.match(r'^## ' + re.escape(section_name) + r'\s*$', line, re.IGNORECASE):
            in_section = True
            continue
        if in_section:
            if line.startswith("## "):
                break
            stripped = line.strip()
            if stripped.startswith("- ") or stripped.startswith("* "):
                items.append(stripped[2:].strip())
    return items

def has_unmet_prerequisites(yak, name_to_state):
    """Check if any prerequisite in ## Prerequisites is not 'done'."""
    items = parse_section_items(yak.get("context"), "Prerequisites")
    for item in items:
        prereq_name = re.sub(r'\s*must be done\s*$', '', item)
        if prereq_name in name_to_state and name_to_state[prereq_name] != "done":
            return True
    return False

def has_blocked_by(context):
    """Return True if context has a non-empty '## Blocked By' section."""
    return len(parse_section_items(context, "Blocked By")) > 0

def is_actionable(yak, include_blocked, name_to_state):
    if yak.get("state") != "todo":
        return False
    children = yak.get("children", [])
    if children:
        non_done = [c for c in children if c.get("state") != "done"]
        if non_done:
            return False
    tags = set(yak.get("tags", []))
    if tags & blocking_tags:
        return False
    if not include_blocked:
        if has_unmet_prerequisites(yak, name_to_state):
            return False
        if has_blocked_by(yak.get("context")):
            return False
    return True

flat = flatten(yaks)
name_to_state = build_name_state_map(flat)
actionable = [y for y in flat if is_actionable(y, include_blocked, name_to_state)]
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
