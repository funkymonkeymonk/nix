---
description: End-to-end PR workflow — publish, watch CI, optionally merge
agent: build
---

Orchestrates the full PR workflow: publish (create OR update), watch CI, and
optionally merge. In the new immutable-history model, this script always
requires a `--message`, because every push adds exactly one new commit on top
of the remote tip.

See the `jj` skill for the full design.

## What you must do before calling the script

1. **Generate a conventional-commit message** describing what this round
   publishes. Same rules as `/pr` or `/update`:
   - For a new PR: the message describes the whole PR.
   - For an existing PR: the message describes what this update round ADDS.

2. Decide whether you're creating or updating:
   - **New PR** (no bookmark on `@` yet): also pass `--type` and
     `--description`.
   - **Update PR** (bookmark already tracks a remote): just `--message`.

3. Run one of:
   ```bash
   # New PR
   jj-finish --type feat --description user-auth \
             --message "feat: add user authentication flow"

   # Update existing PR
   jj-finish --message "fix: address review feedback"

   # With auto-merge on CI success
   jj-finish --message "chore: bump deps" --merge
   ```

## After success

**Always run `jj new`** before making more changes. The script publishes a
commit at `@`; if you start editing without `jj new`, you'll end up trying
to modify a pushed commit (and `immutable_heads()` will block you).

## On CI failure

The script pauses and tells you to:
1. Fix the issues locally.
2. Run `jj-update -m "fix: ..."` to push the fix.
3. Press Enter to re-check CI.

Do NOT try to amend the failed commit in place — it's already immutable on
the remote.
