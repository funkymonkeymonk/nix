---
title: "Getting Started with jj"
description: "Hands-on tutorial for learning the Jujutsu workflow used in this repository"
type: tutorial
audience: developer
last-reviewed: 2026-04-08
---

# Getting Started with jj

In this tutorial you'll learn the fundamentals of Jujutsu (jj), the version control system used in this repository. By the end you'll have made a real change, described it as a commit, and pushed a pull request — all using jj.

## What You'll Learn

- The single most important jj concept: the working copy is a commit
- How to start, describe, and update work
- How to create and update a pull request
- How to undo mistakes

## Prerequisites

- This repository cloned and `devenv shell` active
- GitHub CLI (`gh`) authenticated

## Before You Start: Check Where You Are

Always run this first:

```bash
jj status
jj log
```

`jj log` shows the commit graph. The `@` marker is your current commit — your working copy. Everything you do to files is automatically part of `@`.

## Step 1: Start on a Fresh Commit

Before touching any files, create a new empty commit on top of main:

```bash
jj new main
```

This is the jj equivalent of `git checkout -b my-branch`. You now have an empty `@` whose parent is `main`.

**Why this matters:** If you skip `jj new` and just start editing, your changes land in whatever `@` already is — which might be a described commit you didn't mean to modify. `jj new` gives you a clean slate.

Check the log again:

```bash
jj log
```

You'll see `@` sitting above `main`, empty, with no description yet.

## Step 2: Make Changes

Edit files normally. jj watches the filesystem and tracks everything automatically — no `git add` required.

```bash
# Edit something
echo "# My change" >> README.md

# See what's in @ right now
jj diff

# Summary of changed files
jj status
```

Notice: there's no staging area. Every modified file is already "staged" in `@`.

## Step 3: Describe the Commit

When you're happy with the changes, give `@` a message:

```bash
jj describe -m "docs: add note to README"
```

You can re-run `jj describe` any number of times — it just updates the message. There's no amend dance.

```bash
jj log  # @ now has your message
```

## Step 4: Create a PR

Set a bookmark (jj's name for a branch) and push:

```bash
jj bookmark set feat/my-change -r @
jj git push --bookmark feat/my-change
gh pr create --head feat/my-change --fill
```

New bookmarks are automatically tracked by the remote thanks to the `remotes.origin.auto-track-bookmarks` config.

**Bookmark naming convention:**

| Prefix | Use for |
|--------|---------|
| `feat/` | New features |
| `fix/` | Bug fixes |
| `chore/` | Maintenance |
| `hotfix/` | Urgent fixes |

## Step 5: Respond to Review Comments

Got feedback? Make the fix, then squash it into your PR commit:

```bash
# Make the fix in the current working copy
echo "# Fixed" >> README.md

# Fold @ into its parent (the PR commit)
jj squash

# Push the updated commit
jj git push
```

**Never** run `jj bookmark set` again here — that creates a new bookmark and therefore a new PR. `jj squash` + `jj git push` is the correct update pattern.

## Step 6: Sync if Main Has Moved

If main gained new commits while you were working:

```bash
jj git fetch
jj rebase -r @ -d main
jj git push
```

jj will tell you if there are conflicts. They look like this in `jj status`:

```
There are unresolved conflicts at these paths:
  README.md    2-sided conflict
```

Open the file, resolve the markers, then continue:

```bash
jj resolve   # marks the file resolved
jj git push
```

## Step 7: Undo Anything

Made a mistake? jj records every operation:

```bash
jj undo         # Undo the last operation
jj op log       # See the full operation history
jj op restore 3 # Jump back to operation #3
```

This is more powerful than `git reflog` because it understands semantic operations, not just commits.

## Step 8: After the PR Merges

Once merged, move `@` back to main:

```bash
jj git fetch
jj new main
```

Your old workspace or bookmark can be cleaned up:

```bash
jj bookmark delete feat/my-change
```

## What You've Learned

| Concept | jj equivalent |
|---------|--------------|
| Working directory | `@` — the current commit |
| `git add` | Doesn't exist — everything is tracked |
| `git commit -m` | `jj describe -m` |
| `git checkout -b` | `jj new` + `jj bookmark set` |
| `git commit --amend` | `jj describe` (just re-run it) |
| `git push --force` | `jj squash` + `jj git push` |
| `git reflog` | `jj op log` + `jj op restore` |

## Working in Workspaces

When using [jj workspaces](../how-to/use-workspaces.md) for parallel development, the system switch command is workspace-aware:

```bash
# From any workspace directory
s
```

**What happens:**
- Switch detects you're in a workspace (e.g., `fix-build`)
- Automatically runs from the main repo root
- Uses your current jj commit

This lets you work in isolation while still being able to test your changes with a full system rebuild.

## What's Next

- **[JJ Mental Model](../explanation/jj-mental-model.md)** — why jj works this way, change IDs vs commit IDs, conflicts as first-class objects
- **[How to Create a PR](../how-to/create-pr-with-jj.md)** — the full PR workflow with `jj-pr`
- **[How to Update a PR](../how-to/update-existing-pr.md)** — handling review iterations
- **[How to Use Workspaces](../how-to/use-workspaces.md)** — work on multiple features simultaneously
- **[JJ Commands Reference](../reference/jj-commands.md)** — every command with options
