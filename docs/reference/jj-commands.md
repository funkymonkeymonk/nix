---
title: "JJ Commands Reference"
description: "Complete reference for all jj commands, aliases, and workflow tools"
type: reference
audience: developer
last-reviewed: 2026-04-07
---

# JJ Commands Reference

Complete reference for Jujutsu (jj) commands and the associated workflow tools.

## Core JJ Commands

### Repository Operations

| Command | Description | Example |
|---------|-------------|---------|
| `jj init <path>` | Initialize new jj repo | `jj init my-project` |
| `jj git init --colocate` | Initialize jj in existing git repo | `jj git init --colocate` |
| `jj git clone <url>` | Clone a git repository | `jj git clone https://github.com/owner/repo` |
| `jj git fetch` | Fetch from remote | `jj git fetch` |
| `jj status` | Show working copy status | `jj status` |

### Commit Operations

| Command | Description | Example |
|---------|-------------|---------|
| `jj new` | Create new empty commit | `jj new` |
| `jj new <revision>` | Create commit on top of revision | `jj new main` |
| `jj describe -m "msg"` | Set commit message | `jj describe -m "feat: Add feature"` |
| `jj squash` | Fold changes into parent | `jj squash` |
| `jj absorb` | Auto-distribute changes to ancestors | `jj absorb` |
| `jj diff` | Show changes in working copy | `jj diff` |
| `jj diff --stat` | Show summary of changes | `jj diff --stat` |

### History Operations

| Command | Description | Example |
|---------|-------------|---------|
| `jj log` | Show commit history | `jj log` |
| `jj log -r @` | Show current commit | `jj log -r @` |
| `jj log --no-graph` | Linear history view | `jj log --no-graph` |
| `jj op log` | Show operation history | `jj op log` |
| `jj undo` | Undo last operation | `jj undo` |
| `jj op restore <id>` | Restore to operation | `jj op restore 123` |

### Bookmark Operations

| Command | Description | Example |
|---------|-------------|---------|
| `jj bookmark set <name> -r @` | Create bookmark | `jj bookmark set feat/x -r @` |
| `jj bookmark delete <name>` | Delete bookmark | `jj bookmark delete feat/x` |
| `jj bookmark list` | List all bookmarks | `jj bookmark list` |
| `jj bookmark list -r @` | Show bookmark at @ | `jj bookmark list -r @` |
| `jj bookmark forget <name>` | Remove bookmark (keep commit) | `jj bookmark forget feat/x` |

### Push/Pull Operations

| Command | Description | Example |
|---------|-------------|---------|
| `jj git push` | Push current commit | `jj git push` |
| `jj git push --bookmark <name>` | Push specific bookmark | `jj git push --bookmark feat/x` |
| `jj git push --allow-new` | Allow pushing new bookmark | `jj git push --bookmark feat/x --allow-new` |
| `jj git pull` | Pull changes | `jj git pull` |

### Rebase Operations

| Command | Description | Example |
|---------|-------------|---------|
| `jj rebase -r @ -d <target>` | Rebase current onto target | `jj rebase -r @ -d main` |
| `jj rebase -s <commit> -d <target>` | Rebase subtree | `jj rebase -s abc -d main` |

### Workspace Operations

| Command | Description | Example |
|---------|-------------|---------|
| `jj workspace add <path>` | Create workspace | `jj workspace add ~/workspaces/x` |
| `jj workspace forget <path>` | Remove workspace | `jj workspace forget ~/workspaces/x` |
| `jj workspace list` | List workspaces | `jj workspace list` |
| `jj root` | Show repo root | `jj root` |

### Conflict Resolution

| Command | Description | Example |
|---------|-------------|---------|
| `jj resolve` | Mark conflicts resolved | `jj resolve` |
| `jj resolve --list` | List conflicted files | `jj resolve --list` |

## Workflow Tools (Scripts)

### jj-pr

Create a new PR with conventional branch naming.

```bash
jj-pr <type> <description> [commit-message]
```

**Types:** feat, fix, chore, hotfix, release

**Examples:**
```bash
jj-pr feat user-auth "Add user authentication"
jj-pr fix null-pointer
jj-pr chore deps-update "Update dependencies"
```

### jj-update

Update an existing PR by squashing changes.

```bash
jj-update [new-commit-message]
```

**Examples:**
```bash
jj-update                          # Squash with current message
jj-update "Fix review comments"   # Squash with new message
```

### jj-sync

Sync with main branch.

```bash
jj-sync [base-branch]
```

**Examples:**
```bash
jj-sync           # Rebase onto main
jj-sync develop   # Rebase onto develop
```

### jj-finish

Complete PR workflow: push, create PR, watch CI, merge.

```bash
jj-finish [options]
```

**Options:**
- `--merge` - Prompt to merge on success
- `--max-retries N` - Limit retry attempts (default: 5)
- `--dry-run` - Show what would be done

**Examples:**
```bash
jj-finish                 # Push, create PR, watch CI
jj-finish --merge         # Also prompt to merge
jj-finish --max-retries 3 # Limit to 3 retries
```

### jj-stack

Create stacked PR on top of current branch.

```bash
jj-stack <type> <description> [commit-message]
```

**Example:**
```bash
jj-stack feat api-endpoints "Add API endpoints"
```

### jj-workspace

Manage jj workspaces.

```bash
jj-workspace <command> [args]
```

**Commands:**
- `create <type/topic> [base]` - Create workspace
- `list` - List workspaces
- `remove <name>` - Remove workspace
- `clean` - Remove all workspaces
- `status` - Show workspace status

**Examples:**
```bash
jj-workspace create feat/user-auth
jj-workspace create fix/bug develop
jj-workspace list
jj-workspace remove feat-user-auth-20260115-a1b2
```

### jj-workspace-session

Manage workspace sessions for fast sync.

```bash
jj-workspace-session <action> [args]
```

**Actions:**
- `start [type/topic] [base]` - Start session
- `stop` - End session
- `status` - Show sessions
- `touch` - Reset TTL
- `sync` - Manual sync
- `prune` - Remove expired sessions

**Examples:**
```bash
jj-workspace-session start feat/auth
jj-workspace-session status
jj-workspace-session sync
jj-workspace-session stop
```

## fjj Commands (Multi-Agent Workflow)

### Main Commands

| Command | Description | Alias |
|---------|-------------|-------|
| `fjj [type/topic] [repo]` | Create/goto workspace | - |
| `fjj --add [owner/repo]` | Add repo to mirrors | `fjj-add` |
| `fjj --list` | List workspaces | `fjj-list` |
| `fjj --clean` | Clean merged workspaces | `fjj-clean` |
| `fjj --status` | Show status | `fjj-status` |
| `fjj --session [action]` | Session management | `fjj-session` |

### Interactive Shortcuts

- **Alt-a** - FZF-powered repo picker for `fjj --add`

### Examples

```bash
# Interactive mode
fjj

# Create workspace
fjj feat/my-feature

# Create workspace in specific repo
fjj fix/bug nixpkgs

# Add repository
fjj --add owner/repo
fjj-add owner/repo

# List and clean
fjj-list
fjj-clean
```

## GitHub CLI Integration

### PR Operations

```bash
gh pr create --head <branch> --fill
g h pr view <branch>
gh pr checks --watch
gh pr merge --squash --delete-branch
```

### Repo Operations

```bash
gh repo clone <owner/repo> <path>
gh repo view <owner/repo>
gh repo list --limit 100
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `FJJ_MIRROR_ROOT` | Mirror storage location | `/srv/github` (Linux), `~/src` (macOS) |
| `FJJ_WORKSPACE_ROOT` | Workspace location | `~/workspaces` |
| `JJ_WORKSPACES_DIR` | Workspaces directory | `./workspaces` |
| `JJ_FINISH_MAX_RETRIES` | Max retry attempts | `5` |

## Aliases Reference

### jj Aliases (Built-in Configuration)

| Alias | Expands To | Description |
|-------|------------|-------------|
| `jj ba` | `jj bookmark advance` | Move bookmark forward to child commit |

### Using Aliases

```bash
# Instead of:
jj bookmark advance <bookmark>

# Use:
jj ba <bookmark>
```

### Shell Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `fjj-add` | `fjj --add` | Add repo shortcut |
| `fjj-list` | `fjj --list` | List workspaces |
| `fjj-clean` | `fjj --clean` | Clean workspaces |
| `fjj-status` | `fjj --status` | Show status |
| `fjj-session` | `fjj --session` | Session management |

## Template Strings

jj uses template strings for customizing output:

### Common Templates

```bash
# Show commit ID and description
jj log -T 'concat(change_id.short(), " ", description.first_line())'

# Show bookmarks
jj log -T 'bookmarks'

# Show author and date
jj log -T 'author.email() ++ " " ++ timestamp'
```

## Quick Reference Card

```
START WORK
  jj new                    # Create new commit
  jj status                 # Check state

MAKE CHANGES
  # Edit files...
  jj diff                   # See changes
  jj describe -m "msg"      # Set message

CREATE PR
  jj-pr feat name "msg"     # Create PR
  jj-update                 # Update PR

COMPLETE
  jj-finish --merge         # Push, watch, merge
  fjj --clean               # Clean workspace
```

## See Also

- [JJ Tutorial](../tutorials/jj-workflow.md)
- [JJ Mental Model](../explanation/jj-mental-model.md)
- [How to Create a PR](../how-to/create-pr-with-jj.md)
