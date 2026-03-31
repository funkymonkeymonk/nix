---
description: Create a stacked PR on top of current branch
agent: build
---

Create a stacked PR with the correct base branch for PR stacking.

Use the jj skill for reference. The script is at `jj-stack` in PATH.

Expected arguments: `<type> <description> [commit-message]`

Types: feat, fix, hotfix, release, chore

Run: `jj-stack $ARGUMENTS`

If the user didn't provide arguments, ask for:
1. Type (feat/fix/hotfix/release/chore)
2. Description (kebab-case)
3. Optional commit message
