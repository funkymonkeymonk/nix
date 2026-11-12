---
title: "Create Stacked PRs with jj"
description: "Build dependent pull requests with native Jujutsu commands"
type: how-to
audience: developer
last-reviewed: 2026-11-11
---

# Create Stacked PRs with jj

Create a sequence of pull requests where each branch builds on the previous
one. The Nix flake does not install the former `jj-stack` or `jj-finish`
wrappers; use native Jujutsu and GitHub CLI commands.

## Create the first PR

1. Describe your current change and set a bookmark:

   ```bash
   jj describe -m "feat: add core API"
   jj bookmark set feat/core-api -r @
   ```

2. Push the bookmark and open a PR:

   ```bash
   jj git push --bookmark feat/core-api
   gh pr create --head feat/core-api --base main --fill
   ```

## Create a dependent PR

1. Start a new change on the first bookmark:

   ```bash
   jj new feat/core-api
   ```

2. Make and describe the dependent change. Then create its bookmark:

   ```bash
   jj describe -m "feat: add API client"
   jj bookmark set feat/api-client -r @
   ```

3. Push the new bookmark and set the first PR as its base:

   ```bash
   jj git push --bookmark feat/api-client
   gh pr create --head feat/api-client --base feat/core-api --fill
   ```

Repeat these steps for each additional dependent change. Create each change on
the bookmark that it depends on.

## Update a stack

Push updates by bookmark. Do not rewrite commits that have already been
pushed. If the base PR changes, merge the new base into the dependent change,
move its bookmark, push it, and update the PR's base in GitHub.

For workspace commands and the Jujutsu model, see [Use Workspaces](use-workspaces.md)
and the [JJ Commands Reference](../reference/jj-commands.md).
