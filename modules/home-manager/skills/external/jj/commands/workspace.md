---
description: Manage jj workspaces for multi-project isolation
agent: build
---

Manage jj workspaces for isolating work.

Workspaces live in `~/workspaces/` — never as sibling directories inside the repo.

Use `jj-workspace` to create and manage workspaces:

```bash
jj-workspace create feat/my-topic              # Create workspace from main
jj-workspace create fix/bug-name develop       # Create workspace from develop branch
jj-workspace list                              # Show all workspaces
jj-workspace clean                             # Remove all workspaces
```

Naming convention: `<type>/<topic>-<date>-<id>`
Types: feat, fix, hotfix, chore, release

**Agent naming**: `feat/agent-<agent-id>-<topic>` (e.g. `feat/agent-openclaw-auth-fix`)

After PR is merged, clean up:
```bash
jj-workspace remove <workspace-name>
```

If no arguments, show workspace list and ask what they want to do.
