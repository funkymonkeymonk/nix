---
title: "Update an Existing PR"
description: "Push new changes to an existing Jujutsu pull request"
type: how-to
audience: developer
last-reviewed: 2026-11-11
---

# Update an Existing PR

Use native Jujutsu commands to update a pull request. The Nix flake does not
install the former `jj-update` wrapper.

## Prerequisites

- You have an open pull request.
- The local bookmark tracks that pull request.
- You are in the corresponding Jujutsu workspace.

## Update the PR

1. Check the current workspace and bookmark:

   ```bash
   jj status
   jj bookmark list
   ```

2. Make and describe your changes:

   ```bash
   jj describe -m "feat: update authentication"
   ```

3. Push the existing bookmark:

   ```bash
   jj git push --bookmark feat/user-auth
   ```

4. Verify the update:

   ```bash
   gh pr view feat/user-auth
   ```

Do not create a new bookmark for an update. A new bookmark creates a separate
pull request.

If you want one commit in the PR, use `jj squash` before pushing. Do not rewrite
commits that have already been pushed. See the [JJ Commands Reference](../reference/jj-commands.md).
