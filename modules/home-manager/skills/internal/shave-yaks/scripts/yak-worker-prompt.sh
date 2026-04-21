#!/usr/bin/env bash
# yak-worker-prompt.sh - Generate a complete subagent implementation prompt for a yak
#
# Outputs a fully-formed prompt that can be sent to a subagent to implement
# the yak end-to-end: workspace → implement (TDD/BDD) → PR → CI → merge → done.
#
# Usage:
#   ./yak-worker-prompt.sh "yak name" [--repo-root /path/to/repo]
#
# Output: prompt text on stdout

set -euo pipefail

YAK_NAME="${1:-}"
REPO_ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || jj root 2>/dev/null || pwd)}"
GH_REPO=""

if [[ -z "$YAK_NAME" ]]; then
    echo "Usage: $0 \"yak name\" [repo-root]" >&2
    exit 1
fi

# Get GitHub repo
GH_REPO=$(jj git remote list 2>/dev/null | grep -E '^origin\s' | awk '{print $2}' \
    | sed -E 's#^(git@github\.com:|https://github\.com/)##' \
    | sed -E 's#\.git$##' \
    | sed -E 's#^https://[^@]+@github\.com/##' \
    || echo "")

# Get yak details as JSON
yak_json=$(yx show "$YAK_NAME" --format json 2>/dev/null)
context=$(echo "$yak_json" | python3 -c "import json,sys; y=json.load(sys.stdin); print(y.get('context','(no context)'))")
tags=$(echo "$yak_json" | python3 -c "import json,sys; y=json.load(sys.stdin); print(' '.join(y.get('tags',[])))")
parent=$(echo "$yak_json" | python3 -c "
import json,sys
y=json.load(sys.stdin)
bc = y.get('breadcrumb',[])
print(' > '.join(bc) if bc else 'root')
" 2>/dev/null || echo "")

# Generate a slug from the yak name (lowercase, hyphens, max 40 chars)
slug=$(echo "$YAK_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-*$//' | cut -c1-40)
# Determine branch type from name heuristics
branch_type="fix"
if echo "$YAK_NAME" | grep -qiE '^(add|create|implement|wire|enable|introduce)'; then
    branch_type="feat"
elif echo "$YAK_NAME" | grep -qiE '^(test|coverage|spec)'; then
    branch_type="test"
elif echo "$YAK_NAME" | grep -qiE '^(refactor|consolidate|extract|move|rename|remove|clean)'; then
    branch_type="chore"
fi
branch_name="${branch_type}/${slug}"
workspace_name="${branch_type}-${slug}"

cat <<PROMPT
You are working in the Nix system configuration repository at ${REPO_ROOT}.

## Your Yak

**Name:** ${YAK_NAME}
**Parent:** ${parent}
**Tags:** ${tags:-none}

## Context & Acceptance Criteria

${context}

## Required Workflow

### 1. Setup — fresh workspace off main

\`\`\`bash
cd ${REPO_ROOT}
jj git fetch
jj workspace add --name ${workspace_name} .workspaces/${workspace_name}
\`\`\`

Work in \`.workspaces/${workspace_name}\` but run devenv tasks from the repo root.

### 2. Understand before implementing

Read all relevant files mentioned in the context above. Run:
\`\`\`bash
devenv tasks run check:lint   # understand the baseline
\`\`\`

### 3. Implement using TDD/BDD

**Write tests FIRST, then the implementation.**

- Tests must be written before implementation code
- Each acceptance criterion above maps to at least one test
- Tests should be BDD-style: describe the DESIRED OUTCOME, not the mechanism
- For Nix modules: use \`lib.evalModules\` with a stub to verify option behavior
- For shell scripts: use a bash test with mock filesystem structures
- For CI/workflow changes: write a check that verifies the file structure is correct

The pattern used in this codebase:
- Nix tests live in \`tests/\` as \`.nix\` files
- Tests are \`pkgs.runCommand\` derivations that exit 0 on success
- New tests wire into \`tests/default.nix\`, \`flake.nix\` checks, and a devenv task

### 4. Validate locally before committing

\`\`\`bash
# From repo root:
devenv tasks run check:lint
devenv tasks run test:darwin-eval   # catches module errors
# Build the new check:
git add -A
nix build --impure ".#checks.aarch64-darwin.<test-name>" --no-link
\`\`\`

### 5. Commit (jj, not git)

\`\`\`bash
jj describe -m "<type>: <what and why, referencing the yak>

<body explaining what changed and why>"
\`\`\`

### 6. Push and create PR

\`\`\`bash
jj bookmark set ${branch_name} -r @
jj git push --bookmark ${branch_name}
gh pr create \\
  --title "<type>: <concise description>" \\
  --head "${branch_name}" \\
  --body "\$(cat <<'EOF'
## Summary
- What changed and why (1-3 bullets)

## Acceptance Criteria Met
$(echo "$context" | grep -oE '- \[.\] .*' | head -10 || echo "- See yak context")

## Testing
- Tests added: <list>
- Local validation: lint + darwin-eval + nix build check
EOF
)"
\`\`\`

### 7. Watch CI and merge

Poll until all checks complete:
\`\`\`bash
# Poll every 30-60 seconds:
gh pr view <number> --repo ${GH_REPO} --json statusCheckRollup
\`\`\`

Wait for ALL checks to show \`"conclusion":"SUCCESS"\` and \`"status":"COMPLETED"\`, then:
\`\`\`bash
gh pr merge <number> --repo ${GH_REPO} --squash --delete-branch --admin
\`\`\`

### 8. Mark yak done and clean up

\`\`\`bash
yx done "${YAK_NAME}"
yx sync
jj git fetch
cd ${REPO_ROOT}
jj workspace forget ${workspace_name}
rm -rf .workspaces/${workspace_name}
\`\`\`

## Critical Rules

- **Tests first** — write failing tests before any implementation code
- **Use \`jj describe\`** not \`git commit\` — the working copy IS the commit
- **\`git add -A\` before \`nix build --impure\`** — staged files must be visible
- **Run devenv tasks from repo root**, not from workspace
- **alejandra formats Nix** — \`check:lint\` will fail on unformatted code (run \`alejandra .\` to fix)
- **Check both platforms**: Darwin eval is required; NixOS eval if you touched NixOS-only modules
- **If CI fails**: investigate the failure, fix it, push an update (jj squash + jj git push), do NOT merge broken code

## Return

When done, report:
1. PR URL and number
2. Whether merged successfully
3. Final commit hash on main
4. Any issues encountered or open questions
PROMPT
