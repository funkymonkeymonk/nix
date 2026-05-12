---
description: Create a new PR with conventional branch naming
agent: build
---

Create a new PR. Collapses all local work into a single commit on top of the
base branch's remote tip, then pushes and opens a PR via `gh`.

See the `jj` skill (SKILL.md → "Creating a PR") for the full design.

## What you must do before calling the script

1. Run `jj git fetch` (the script will also do this).
2. Inspect the diff between the base and `@`:
   ```bash
   jj diff -r "main@origin..@"
   ```
3. **Generate a conventional-commit message** that describes the whole PR —
   the single commit that will represent it. Examples:
   - `feat: add user authentication flow with JWT`
   - `fix: guard against null user in OAuth callback`
   - `chore: bump dependencies to latest patch versions`

4. Determine type (feat/fix/hotfix/release/chore) and a kebab-case
   description for the branch name.
5. Run: `jj-pr <type> <description> --message "<your generated message>"`

   If the base is not `main`, add `--base <branch>`.

## After the script succeeds

**Always run `jj new`** before making more changes. The script reminds you
of this.

Your previous local commits are orphaned (recoverable via `jj op log`). Do
NOT continue working from them — the pushed commit is the new source of
truth.

## If the user didn't provide arguments

Ask for:
1. Type (feat/fix/hotfix/release/chore).
2. Description (kebab-case, e.g. `user-auth`, `fix-login`).

You generate the message yourself from the diff — don't ask the user to
write it unless the diff is genuinely ambiguous.
