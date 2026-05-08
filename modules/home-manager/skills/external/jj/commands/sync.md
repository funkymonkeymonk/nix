---
description: Merge main into the current branch (no rebase, no force push)
agent: build
---

Merge the latest `main` (or specified base) into the current branch by
creating a merge commit with two parents. **Never rebases**; preserves the
immutability of pushed commits.

See the `jj` skill (SKILL.md → "Syncing with main") for the full design.

## What you must do before calling the script

1. If you have unpushed local work, decide whether to push it first with
   `/update` — `jj-sync` merges from `<current-bookmark>@origin`, so
   unpushed local work is NOT included in the sync commit.
2. Run: `jj-sync` (or `jj-sync --base develop` for a different base)

The script:
1. Fetches.
2. Checks whether base is already merged in (no-op if so).
3. Creates a merge commit with parents (`<bookmark>@origin`, `<base>@origin`).
4. Pushes.

## After the script succeeds

**Always run `jj new`** before making more changes.

## Why merge, not rebase?

Rebasing rewrites the pushed commits on your branch, which violates the
"pushed commits are immutable" principle and requires a force push. Merging
adds a new commit with the latest base as one of its parents, preserving
all existing commit hashes.
