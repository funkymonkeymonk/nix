---
description: Sync with main branch (fetch and rebase)
agent: build
---

Sync the current branch with main (or specified base branch).

Use the jj skill for reference. The script is at `jj-sync` in PATH.

Run: `jj-sync $ARGUMENTS`

Optional argument: base branch (defaults to main)

Examples:
- `jj-sync` - Fetch and rebase onto main
- `jj-sync develop` - Rebase onto develop
