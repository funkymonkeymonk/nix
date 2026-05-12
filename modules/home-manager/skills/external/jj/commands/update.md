---
description: Update an existing PR by adding one new commit on top of the remote tip
agent: build
---

Update an existing PR by appending a single new commit on top of the PR's
remote tip. **Never** rewrites pushed commits; no force pushes.

See the `jj` skill (SKILL.md → "Updating a PR") for the full design.

## What you must do before calling the script

1. Run `jj git fetch` (the script will also do this, but doing it early lets you inspect state).
2. Inspect the diff between the remote tip and `@`:
   ```bash
   BOOKMARK=$(jj log -r @ --no-graph -T 'bookmarks' | head -1)
   jj diff -r "${BOOKMARK}@origin..@"
   ```
   If that range is empty, include the working-copy diff: `jj diff`.
3. **Generate a conventional-commit message** that describes the net change
   this update adds to the PR. Examples:
   - `fix: address review feedback on error handling`
   - `feat: add pagination to user list endpoint`
   - `refactor: extract auth middleware into separate module`

   The message should describe what this update round ADDS, not the whole PR.

4. Run: `jj-update --message "<your generated message>"`

## After the script succeeds

**Always run `jj new`** to start a fresh empty commit on top of the pushed
commit. The script reminds you of this; heed it.

Your previous local commits are orphaned (still recoverable via `jj op log`
if needed). Do NOT try to navigate back to them — the pushed commit is the
new source of truth.

## If the script errors with "No bookmark on @"

Run `/pr` first to create the PR.
