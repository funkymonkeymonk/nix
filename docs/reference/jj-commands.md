---
title: "JJ Commands Reference"
description: "Complete reference for Jujutsu (jj) commands used in this repository"
type: reference
audience: developer
last-reviewed: 2026-04-08
---

# JJ Commands Reference

Complete reference for Jujutsu (jj) commands. For workflow context see the [tutorial](../tutorials/jj-workflow.md) and [how-to guides](../how-to/create-pr-with-jj.md).

## Core Concepts

- `@` — the current working copy commit
- Change ID — stable identifier (survives rebase/edit), shown in jj log
- Commit ID — git-compatible SHA, changes on every edit
- Bookmark — jj's name for a branch; a mutable pointer to a commit

---

## Status and Navigation

| Command | Description |
|---------|-------------|
| `jj status` | Show changed files in `@` |
| `jj log` | Show commit graph (default: relevant commits) |
| `jj log -r 'all()'` | Show all commits |
| `jj log --limit N` | Show N commits |
| `jj diff` | Show diff of `@` |
| `jj diff -r <rev>` | Show diff of a specific revision |
| `jj diff --stat` | Show changed file names and counts only |
| `jj show <rev>` | Show commit metadata and diff |

---

## Creating and Describing Commits

| Command | Description |
|---------|-------------|
| `jj new` | Create new empty commit on top of `@` |
| `jj new <rev>` | Create new empty commit on top of `<rev>` |
| `jj new <rev1> <rev2>` | Create merge commit |
| `jj describe -m "msg"` | Set message on `@` |
| `jj describe -r <rev> -m "msg"` | Set message on a specific commit |

---

## Modifying History

| Command | Description |
|---------|-------------|
| `jj squash` | Fold `@` into its parent |
| `jj squash -r <rev>` | Fold `<rev>` into its parent |
| `jj squash --from <rev> --into <rev>` | Fold one commit into another |
| `jj absorb` | Distribute `@` changes into ancestors that introduced each changed line |
| `jj rebase -r @ -d <rev>` | Move `@` to be a child of `<rev>` |
| `jj rebase -s <rev> -d <rev>` | Move `<rev>` and all its descendants |
| `jj split` | Interactively split `@` into two commits |
| `jj edit <rev>` | Move `@` to edit an existing commit |

---

## Bookmarks (Branches)

| Command | Description |
|---------|-------------|
| `jj bookmark list` | List all bookmarks |
| `jj bookmark set <name> -r @` | Point `<name>` at `@` |
| `jj bookmark set <name> -r <rev>` | Point `<name>` at `<rev>` |
| `jj bookmark delete <name>` | Delete a bookmark |
| `jj bookmark track <name> --remote origin` | Track a remote bookmark |
| `jj bookmark advance <name>` | Advance bookmark forward (alias: `jj ba`) |

**Naming convention:** `<type>/<description>` — e.g. `feat/user-auth`, `fix/null-pointer`, `chore/update-deps`

---

## Git Interop

| Command | Description |
|---------|-------------|
| `jj git fetch` | Fetch from all remotes |
| `jj git fetch --remote origin` | Fetch from a specific remote |
| `jj git push` | Push tracked bookmarks |
| `jj git push --bookmark <name>` | Push a specific bookmark |
| `jj git export` | Flush jj state to git refs |
| `jj git import` | Import git ref changes into jj |
| `jj git remote list` | List configured remotes |
| `jj git remote add <name> <url>` | Add a remote |

---

## Workspaces

| Command | Description |
|---------|-------------|
| `jj workspace list` | List all workspaces and their `@` |
| `jj workspace add <path>` | Create a new workspace |
| `jj workspace add --name <name> <path>` | Create with explicit name |
| `jj workspace forget <name>` | Remove a workspace (keeps the directory) |

See [How to Use Workspaces](../how-to/use-workspaces.md) for the full workflow including `jj-workspace` tooling.

---

## Undo and Recovery

| Command | Description |
|---------|-------------|
| `jj undo` | Undo the last operation |
| `jj op log` | Show the operation history |
| `jj op restore <id>` | Restore repository state to a past operation |

---

## Conflict Resolution

| Command | Description |
|---------|-------------|
| `jj resolve` | Open the configured merge tool |
| `jj resolve --list` | List all conflicted files |

jj can store unresolved conflicts in commits — you are not forced to resolve them immediately. A commit with a conflict is marked with `(conflict)` in `jj log`.

---

## Revsets (Querying the Graph)

Revsets are expressions for selecting commits, used in `-r` arguments.

| Expression | Selects |
|------------|---------|
| `@` | Current working copy |
| `main` | The `main` bookmark |
| `main@origin` | Remote tracking bookmark |
| `@-` | Parent of `@` |
| `@+` | Children of `@` |
| `::@` | All ancestors of `@` (inclusive) |
| `main..@` | Commits in `@` not in `main` |
| `all()` | Every commit |
| `description("fix")` | Commits whose message contains "fix" |
| `author("name")` | Commits by author |

---

## Aliases Configured in This Repo

| Alias | Expands to |
|-------|-----------|
| `jj ba` | `jj bookmark advance` |

---

## Workflow Scripts

These scripts are installed by the `developer` role and wrap common multi-step jj workflows:

| Script | Purpose |
|--------|---------|
| `jj-pr <type> <desc>` | Create bookmark, push, open PR |
| `jj-update [msg]` | Squash and push to update existing PR |
| `jj-sync [base]` | Fetch and rebase onto main (or `base`) |
| `jj-finish [--merge]` | End-to-end: push → PR → watch CI → merge |
| `jj-stack <type> <desc>` | Create stacked PR on current branch |
| `jj-workspace <cmd>` | Manage named workspaces |
| `jj-workspace-session <cmd>` | Manage OpenCode workspace sessions with fast-sync |

See [Complete PR Workflow](../how-to/complete-pr-workflow.md) for `jj-finish` usage.

---

## See Also

- [Getting Started with jj](../tutorials/jj-workflow.md) — hands-on introduction
- [JJ Mental Model](../explanation/jj-mental-model.md) — why jj works the way it does
- [How to Create a PR](../how-to/create-pr-with-jj.md)
- [How to Update a PR](../how-to/update-existing-pr.md)
- [How to Sync with Main](../how-to/sync-with-main.md)
- [How to Use Workspaces](../how-to/use-workspaces.md)
- [Official jj docs](https://martinvonz.github.io/jj/latest/)
