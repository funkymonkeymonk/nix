---
title: "Create a PR with jj"
description: "Create and push a Jujutsu bookmark, then open a GitHub pull request"
type: how-to
audience: developer
last-reviewed: 2026-11-11
---

# Create a PR with jj

Use native Jujutsu and GitHub CLI commands to create a pull request. The Nix
flake does not install the former `jj-pr` wrapper.

## Prerequisites

- You are in a Jujutsu repository with a remote.
- GitHub CLI is authenticated.
- Your changes are ready to push.

## Create and push the bookmark

1. Describe the current change:

   ```bash
   jj describe -m "feat: add user authentication"
   ```

2. Create a bookmark for the pull request:

   ```bash
   jj bookmark set feat/user-auth -r @
   ```

3. Push the bookmark:

   ```bash
   jj git push --bookmark feat/user-auth
   ```

4. Create the pull request:

   ```bash
   gh pr create --head feat/user-auth --fill
   ```

5. Verify the pull request:

   ```bash
   gh pr view feat/user-auth
   ```

Use a bookmark name that follows `<type>/<description>`, such as
`feat/user-auth`, `fix/null-pointer`, or `chore/update-deps`.

## Troubleshooting

If the bookmark already exists, choose another name or delete the old bookmark:

```bash
jj bookmark delete feat/user-auth
```

If the push fails, check the remote and your access:

```bash
jj git remote list
```

For native jj commands, see the [JJ Commands Reference](../reference/jj-commands.md).
