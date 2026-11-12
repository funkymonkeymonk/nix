---
title: "Sync with Main Branch"
description: "Merge the latest remote main commit into a Jujutsu workspace"
type: how-to
audience: developer
last-reviewed: 2026-11-11
---

# Sync with Main Branch

Use native Jujutsu commands to merge the latest remote `main` into your
workspace. The Nix flake does not install the former `jj-sync` wrapper or a
scheduled sync session.

## Sync the workspace

1. Fetch remote bookmarks:

   ```bash
   jj git fetch
   ```

2. Create a merge commit with the remote main and your current change:

   ```bash
   jj new main@origin @
   ```

3. Move your bookmark to the merge commit and push it:

   ```bash
   jj bookmark set feat/my-feature -r @
   jj git push --bookmark feat/my-feature
   ```

Use your actual bookmark name instead of `feat/my-feature`. This merge-based
workflow keeps pushed commits unchanged.

## Resolve conflicts

Check for conflicts:

```bash
jj status
```

Edit the conflicted files, then mark them resolved:

```bash
jj resolve
```

After resolution, update the bookmark and push the merge commit.

## Verify the sync

Run `jj log` and confirm that your work now has `main@origin` in its ancestry.
For more commands, see the [JJ Commands Reference](../reference/jj-commands.md).
