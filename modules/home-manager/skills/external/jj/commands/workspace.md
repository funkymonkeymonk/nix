---
description: Manage jj workspaces for multi-project isolation
agent: build
---

Manage jj workspaces for isolating work.

Use the jj skill for reference. The script is at `jj-workspace` in PATH.

Run: `jj-workspace $ARGUMENTS`

Commands:
- `create <type/topic> [base]` - Create new workspace (e.g., feat/user-auth)
- `list` - Show all workspaces
- `remove <name>` - Remove a workspace
- `clean` - Remove all workspaces  
- `status` - Status of all workspaces

Naming convention: `<type>/<topic>-<date>-<id>`
Types: feat, fix, hotfix, chore, release

If no arguments, show workspace list and ask what they want to do.
