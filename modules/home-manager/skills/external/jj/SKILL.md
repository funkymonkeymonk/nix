---
name: jj
description: Use Jujutsu (jj) for version control. Covers workflow, commits, bookmarks with Conventional Branch naming, pushing to GitHub, absorb, squash, stacked PRs, workspaces with auto-sync for OpenCode sessions. Use when working with jj, creating commits, pushing changes, or managing version control.
---

# Jujutsu (jj) Version Control

## Core Principles

### 1. The working copy IS a commit

Changes you make are immediately part of the current commit. There's no staging area.

- Always `jj new` before starting new work
- Use `jj squash` to fold changes into parent (local commits only — see principle 2)
- Use `jj absorb` to auto-distribute fixes to ancestors (local commits only)

### 2. Pushed commits are immutable

Once a commit has been pushed to a remote, treat it as immutable. Never rewrite it. This eliminates force pushes entirely.

Implications:
- Don't `jj squash` into an already-pushed commit
- Don't `jj describe` an already-pushed commit
- Don't `jj rebase` pushed commits onto a new base — **merge** `main` into the branch instead
- When updating a PR, append a single new commit on top of the remote tip (see "Updating a PR" below)

Enforce this at the tool level by setting `immutable_heads()` to include remote bookmarks (see "jj config" section).

### 3. Commit often locally, consolidate once at push time

Between pushes, commit freely — every agent turn, every experiment. Those commits are disposable scratch work. When you're ready to share with the PR, collapse everything since the last push into **one new commit on top of the remote tip** and push it.

This gives you:
- Rich local history to navigate and recover from
- Clean, immutable, review-friendly history on the remote
- No force pushes, ever

## Quick Reference

| Command | Purpose |
|---------|---------|
| `jj status` | Check current state (ALWAYS run first) |
| `jj log` | View commit history |
| `jj diff` | See changes in current commit |
| `jj new` | Create new empty commit |
| `jj describe -m "msg"` | Set commit message (local commits only) |
| `jj squash` | Move changes to parent (local commits only) |
| `jj absorb` | Auto-distribute to ancestors (local commits only) |
| `jj git fetch` | Fetch from remote |
| `jj git push` | Push to remote (fast-forward only) |

## OpenCode Slash Commands

| Command | Purpose |
|---------|---------|
| `/pr` | Create new PR: squash local work onto base, push |
| `/update` | Update existing PR: squash local work onto remote tip, push |
| `/sync` | Merge main into current branch (no rebase) |
| `/finish` | Push, create PR, watch CI |
| `/stack` | Create stacked PR on top of current branch |
| `/push` | Push current bookmark (fast-forward only) |
| `/workspace` | Manage jj workspaces |

## Creating a PR (initial push)

```
Agent:
  1. jj git fetch
  2. Commit local work freely while developing: jj new + jj describe each round
  3. When ready to share:
     a. Generate a conventional-commit message from the complete diff
        (base..@). This is the message for ONE commit representing the
        whole PR.
     b. Run: jj-pr <type> <description> --message "<msg>"
```

`jj-pr` internally:
1. Fetches from remote.
2. Creates a new empty commit directly on top of the base branch (`main@origin`).
3. Restores the tree from your current `@` into that new commit.
4. Sets the bookmark to the new commit.
5. Pushes (fast-forward only).
6. Opens the PR via `gh`.

Your local scratch commits are orphaned but recoverable via `jj op log`. After `jj-pr`, run `jj new` to continue working on top of the pushed commit.

## Updating a PR

**Key rule:** Never rewrite the remote tip. Always add a new commit on top.

```
Agent:
  1. While working, commit locally every change:
       jj new && <make changes> && jj describe -m "wip: whatever"
  2. When ready to update the PR:
     a. Generate a conventional-commit message describing the full
        diff between the remote tip and your current @ — i.e. what
        this update round adds to the PR.
     b. Run: jj-update --message "<msg>"
```

`jj-update` internally:
1. `jj git fetch` — refresh `<bookmark>@origin` to the true remote tip.
2. If no bookmark on `@`, or bookmark has no remote tracking, falls back to the `jj-pr` flow (new PR).
3. If the range `<bookmark>@origin..@` is empty AND working copy is clean → exit cleanly.
4. Create a new empty commit on top of `<bookmark>@origin` with the provided message.
5. Restore the tree from the old `@` into the new commit.
6. Move the bookmark to the new commit.
7. `jj git push` (fast-forward only).

### Resuming work after jj-update

After a successful `jj-update`, your old local commits are **orphaned** (no longer reachable from any bookmark). They are:
- Still in the op-log (recoverable via `jj op log` + `jj op restore`).
- **Not** where you should continue working.

**Always run `jj new` after `jj-update`** to start a fresh empty commit on top of the just-pushed commit. Do not try to check out the orphaned commits — they don't exist on the remote and will only cause confusion.

`jj-update` will print the new pushed commit ID and a reminder to run `jj new`.

## Syncing with main (merge, not rebase)

Rebasing rewrites the pushed commit, which violates principle 2. Instead, merge `main` into the branch:

```bash
jj-sync           # Fetch main, create a merge commit bringing main into your branch
jj-sync develop   # Merge develop instead
```

`jj-sync` internally:
1. `jj git fetch`.
2. If `main@origin` is already an ancestor of `@`, exit cleanly.
3. `jj new <bookmark>@origin main@origin` — create a merge commit with two parents.
4. Move bookmark to the merge commit.
5. Push (fast-forward only).

Then run `jj new` to continue working on top.

## jj Config: Enforcing Immutability

Add to `~/.config/jj/config.toml` (or `$XDG_CONFIG_HOME/jj/config.toml`):

```toml
[revset-aliases]
# Treat all commits reachable from remote bookmarks as immutable.
# This makes jj refuse to rewrite pushed commits.
"immutable_heads()" = "present(trunk()) | remote_bookmarks()"
```

With this config, attempting to `jj squash` or `jj describe` a pushed commit will error out with a clear message, forcing you into the "new commit on top" workflow.

## Conventional Branch Naming

Branch format: `<type>/<description>`

| Type | Purpose | Example |
|------|---------|---------|
| `feat/` | New features | `feat/user-auth` |
| `fix/` | Bug fixes | `fix/null-pointer` |
| `hotfix/` | Urgent fixes | `hotfix/security-patch` |
| `release/` | Releases | `release/v1.2.0` |
| `chore/` | Non-code tasks | `chore/deps-update` |

Rules:
- Lowercase alphanumerics and hyphens only
- No consecutive/leading/trailing hyphens
- Include ticket numbers: `feat/gh-123-add-feature`

## Workspaces (OpenCode sessions)

Workspaces let you isolate work and enable fast background sync.

### Starting a session

```
/workspace feat/user-auth        # Create workspace from main
/workspace fix/login develop     # Create workspace from develop branch
/workspace                       # Enable fast sync in current workspace
```

Or CLI:
```bash
jj-workspace-session start feat/auth
jj-workspace-session start
```

### What happens

1. **Workspace created**: `feat/auth-20260223-a1b2` (type/topic-date-id).
2. **Fast sync enabled**: repository syncs every 5 minutes (vs hourly).
3. **Main stays clean**: your work is isolated, main auto-syncs with upstream.
4. **Session TTL**: auto-expires after 30 minutes of inactivity (resets on each sync).

### Session commands

```bash
jj-workspace-session start [type/topic] [base]
jj-workspace-session stop
jj-workspace-session touch     # Reset TTL manually
jj-workspace-session status
jj-workspace-session sync      # Manual sync
jj-workspace-session prune     # Remove expired sessions
```

### Ending a session

```bash
jj-workspace-session stop
jj-workspace remove <name>     # When fully done
```

### Workspace commands

```bash
jj-workspace create feat/user-auth      # Creates feat/user-auth-<date>-<id>
jj-workspace create fix/bug develop
jj-workspace list
jj-workspace remove <name>
jj-workspace clean                       # Remove all
jj-workspace status
```

## Background Auto-Sync

Repositories opt-in via a `.jj-autosync` config file:

```bash
# .jj-autosync — add to repo root and commit
enabled=true      # Enable hourly sync
main=main         # Main branch name
fast_sync=true    # Enable 5-min sync during sessions
```

| Mode | Frequency | Requires |
|------|-----------|----------|
| Hourly | Every hour | `enabled=true` |
| Session | Every 5 min | `fast_sync=true` + active session |

Status:
```bash
jj-autosync-status    # Show sessions and recent logs
```

Logs:
- `/tmp/jj-autosync.log` — hourly sync
- `/tmp/jj-fast-sync.log` — session sync

Failures trigger cross-platform desktop notifications (via `noti`, `terminal-notifier`, or `notify-send`).

## Manual Workflow (without scripts)

### Create PR

```bash
jj git fetch
# Develop: make many local commits as you go
jj new main@origin
# ... changes ...
jj describe -m "wip"
jj new
# ... more changes ...
jj describe -m "wip 2"

# When ready to push:
OLD=$(jj log -r @ --no-graph -T 'commit_id')
jj new main@origin -m "feat: add user auth"
jj restore --from "$OLD" --to @
jj bookmark set feat/user-auth -r @
jj git push --bookmark feat/user-auth
gh pr create --head feat/user-auth
jj new   # Fresh commit to continue work
```

### Update PR

```bash
jj git fetch
# Each update round:
OLD=$(jj log -r @ --no-graph -T 'commit_id')
jj new 'feat/user-auth@origin' -m "fix: address review feedback"
jj restore --from "$OLD" --to @
jj bookmark set feat/user-auth -r @
jj git push
jj new
```

### Sync with main

```bash
jj git fetch
jj new 'feat/user-auth@origin' 'main@origin' -m "merge main into feat/user-auth"
jj bookmark set feat/user-auth -r @
jj git push
jj new
```

## Common Mistakes

1. **Working in a described commit** — always `jj new` before making changes.
2. **Forgetting `jj new` after an update** — you'll end up squashing onto a pushed commit. Always run `jj new` after `jj-update`, `jj-pr`, or `jj-sync`.
3. **Trying to `jj squash` into a pushed commit** — violates immutability. Use `jj-update` instead.
4. **Rebasing a pushed branch onto new main** — use `jj-sync` (merge) instead.
5. **Reaching for `--force` or `--allow-backwards` on `jj git push`** — if you need force, something upstream is wrong. Stop and re-evaluate.

## Undo

```bash
jj undo              # Undo last operation
jj op log            # View operation history
jj op restore <id>   # Restore to a specific point — also useful to recover orphaned local commits
```
