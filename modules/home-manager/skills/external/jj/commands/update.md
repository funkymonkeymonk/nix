---
description: Update an existing PR (squash changes and push)
agent: build
---

Update an existing PR by squashing current changes into parent commit and pushing.

Use the jj skill for reference. The script is at `jj-update` in PATH.

Run: `jj-update $ARGUMENTS`

Optional argument: new commit message (keeps existing if not provided)

Examples:
- `jj-update` - Squash and push, keep existing message
- `jj-update "Fix review comments"` - Squash with new message
