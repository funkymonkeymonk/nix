---
description: Manage jj workspaces for multi-project isolation
agent: build
---

Manage jj workspaces for isolating work.

Workspaces live in `~/workspaces/` — never as sibling directories inside the repo.

Use `fjj` to create and manage workspaces:

```bash
fjj feat/my-topic              # Create workspace from main
fjj fix/bug-name develop       # Create workspace from develop branch
fjj list                       # Show all workspaces
fjj clean                      # Remove merged/stale workspaces
```

Naming convention: `<type>/<topic>-<date>-<id>`
Types: feat, fix, hotfix, chore, release

**Agent naming**: `feat/agent-<agent-id>-<topic>` (e.g. `feat/agent-openclaw-auth-fix`)

After PR is merged, clean up:
```bash
jj workspace forget <workspace-name>
rm -rf ~/workspaces/<workspace-name>
```

If no arguments, show workspace list and ask what they want to do.
