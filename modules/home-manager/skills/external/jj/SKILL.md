---
name: jj
description: Use Jujutsu (jj) for version control. Covers workflow, commits, bookmarks with Conventional Branch naming, pushing to GitHub, absorb, squash, stacked PRs, workspaces with auto-sync for OpenCode sessions. Use when working with jj, creating commits, pushing changes, or managing version control.
---

# Jujutsu (jj) Version Control

## Key Mental Model

**The working copy IS a commit.** Changes you make are immediately part of the current commit. There's no staging area.

- Always `jj new` before starting new work
- Use `jj squash` to fold changes into parent
- Use `jj absorb` to auto-distribute fixes to ancestors

## Quick Reference

| Command | Purpose |
|---------|---------|
| `jj status` | Check current state (ALWAYS run first) |
| `jj log` | View commit history |
| `jj diff` | See changes in current commit |
| `jj new` | Create new empty commit |
| `jj describe -m "msg"` | Set commit message |
| `jj squash` | Move changes to parent |
| `jj absorb` | Auto-distribute to ancestors |
| `jj git push` | Push to remote |
| `jj git fetch` | Fetch from remote |

## OpenCode Workspace Workflow

When working with OpenCode, use **workspace sessions** to isolate your work and enable fast sync:

### Starting a Session

Use the `/workspace` command in OpenCode:
```
/workspace feat/user-auth        # Create workspace from main
/workspace fix/login develop     # Create workspace from develop branch
/workspace                       # Just enable fast sync in current workspace
```

Or use the CLI directly:
```bash
jj-workspace-session start feat/auth      # Create workspace + start session
jj-workspace-session start                # Start session in current workspace
```

### What Happens

1. **Workspace Created**: `feat/auth-20260223-a1b2` (type/topic-date-id format)
2. **Fast Sync Enabled**: Repository syncs every 5 minutes (vs hourly)
3. **Main Stays Clean**: Your work is isolated, main auto-syncs with upstream
4. **Session TTL**: Sessions auto-expire after 30 minutes of inactivity (TTL resets on each sync)

### Session Commands

```bash
jj-workspace-session start [type/topic] [base]   # Start session
jj-workspace-session stop                         # End session
jj-workspace-session touch                        # Reset TTL manually
jj-workspace-session status                       # Show active sessions
jj-workspace-session sync                         # Manual sync (also resets TTL)
jj-workspace-session prune                        # Remove expired sessions
```

### Ending a Session

```bash
jj-workspace-session stop    # Stops fast sync, keeps workspace
jj-workspace remove <name>   # Remove workspace when done
```

## Workflow Scripts

Use the bundled scripts for common workflows (run from skill's scripts/ directory or add to PATH):

### `jj-pr` - Create New PR

```bash
# Usage: jj-pr <type> <description> [commit-message]
jj-pr feat user-auth "Add user authentication"
jj-pr fix null-pointer
jj-pr chore deps-update
```

Types: `feat`, `fix`, `hotfix`, `release`, `chore`

### `jj-update` - Update Existing PR

```bash
# Usage: jj-update [new-commit-message]
jj-update                        # Squash and push, keep message
jj-update "Fix review comments"  # Squash with new message
```

### `jj-sync` - Sync with Main

```bash
# Usage: jj-sync [base-branch]
jj-sync         # Fetch and rebase onto main
jj-sync develop # Rebase onto develop
```

### `jj-stack` - Stacked PRs

```bash
# Usage: jj-stack <type> <description> [commit-message]
jj-stack feat login-ui "Add login components"
```

Creates PR with correct base branch for stacking.

### `jj-workspace` - Manage Workspaces

```bash
jj-workspace create feat/user-auth      # Creates feat/user-auth-<date>-<id>
jj-workspace create fix/bug develop     # New workspace from develop
jj-workspace list                       # Show all workspaces
jj-workspace remove <name>              # Remove workspace
jj-workspace clean                      # Remove all workspaces
jj-workspace status                     # Status of all workspaces
```

**Naming Convention**: `<type>/<topic>-<date>-<id>`
- Types: `feat`, `fix`, `hotfix`, `chore`, `release`
- Auto-generated date (YYYYMMDD) and 4-char id

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

## Background Auto-Sync

Repositories opt-in to auto-sync by adding a `.jj-autosync` config file:

```bash
# .jj-autosync - add to repo root (commit it to share with team)
enabled=true      # Enable hourly sync
main=main         # Main branch name
fast_sync=true    # Enable 5-min sync during sessions
```

| Mode | Frequency | Requires |
|------|-----------|----------|
| **Hourly** | Every hour | `enabled=true` in `.jj-autosync` |
| **Session** | Every 5 min | `fast_sync=true` + active session |

### Status and Logs

```bash
jj-autosync-status          # Show sessions and recent logs
```

Logs are at:
- `/tmp/jj-autosync.log` - Hourly sync log
- `/tmp/jj-fast-sync.log` - Session sync log

### Notifications

Sync failures trigger cross-platform desktop notifications (using `noti`, `terminal-notifier`, or `notify-send`).

## Manual Workflow (if not using scripts)

### Create PR

```bash
jj new main                              # Start from main
# ... make changes ...
jj describe -m "Add feature"             # Describe
jj bookmark set feat/my-feature -r @     # Create bookmark
jj git push --bookmark feat/my-feature --allow-new
gh pr create --head feat/my-feature
```

### Update PR

```bash
jj new                    # New commit on top
# ... make changes ...
jj squash                 # Fold into PR commit
jj git push               # Push update
```

### Sync with Main

```bash
jj git fetch
jj rebase -r @ -d main
jj git push
```

## Common Mistakes

1. **Working in described commit**: Always `jj new` before making changes
2. **Using `-c @` for updates**: This creates NEW bookmark/PR. Use `jj squash` + `jj git push`
3. **Forgetting `--allow-new`**: Required first time pushing a bookmark

## Undo

```bash
jj undo              # Undo last operation
jj op log            # View operation history
jj op restore <id>   # Restore to specific point
```
