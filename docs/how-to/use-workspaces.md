---
title: "Use Jujutsu Workspaces"
description: "Create and manage isolated working copies with native jj commands"
type: how-to
audience: developer
last-reviewed: 2026-11-11
---

# Use Jujutsu Workspaces

Use native Jujutsu workspace commands to keep independent changes in separate
working copies. The Nix flake does not install the former `jj-workspace` or
`jj-workspace-session` wrappers.

## Create a workspace

1. From the repository, create a workspace under `~/workspaces/`:

   ```bash
   jj workspace add --name feat-my-feature ~/workspaces/feat-my-feature
   ```

2. Enter the workspace and set its starting point:

   ```bash
   cd ~/workspaces/feat-my-feature
   jj new main@origin
   ```

3. Check the workspace:

   ```bash
   jj status
   jj log
   ```

Keep workspace names unique. Use a name that identifies the work, such as
`feat-my-feature` or `fix-login-bug`.

## List workspaces

Run this command from any workspace in the repository:

```bash
jj workspace list
```

## Remove a workspace

1. Leave the workspace directory.
2. Forget the workspace from the repository:

   ```bash
   jj workspace forget feat-my-feature
   ```

3. Remove its directory if it remains:

   ```bash
   rm -rf ~/workspaces/feat-my-feature
   ```

## Work in parallel

Create one workspace for each independent change. Do not edit the same
workspace from multiple agents at the same time. Create and push a separate
bookmark for each PR.

The Nix flake does not provide automatic fast-sync sessions. Fetch remote
changes with `jj git fetch`, then merge the required revision into the current
change. See [Sync with Main](sync-with-main.md) and the [JJ Commands
Reference](../reference/jj-commands.md).
