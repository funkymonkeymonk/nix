---
description: Create a new PR with conventional branch naming
agent: build
---

Create a new PR using jj with conventional branch naming.

Use the jj skill for reference. The script is at `jj-pr` in PATH.

Expected arguments: `<type> <description> [commit-message]`

Types: feat, fix, hotfix, release, chore

Run: `jj-pr $ARGUMENTS`

If the user didn't provide arguments, ask for:
1. Type (feat/fix/hotfix/release/chore)
2. Description (kebab-case, e.g., user-auth, fix-login)
3. Optional commit message
