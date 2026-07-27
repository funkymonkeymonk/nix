---
title: "Use Workspaces"
description: "How to create and manage isolated jj workspaces"
type: how-to
audience: developer
last-reviewed: 2026-04-07
---

# How to Use Workspaces

This guide shows you how to create and manage isolated jj workspaces for parallel development.

## Goal

Create isolated workspaces to work on multiple features or fixes simultaneously.

## Prerequisites

- You're in a jj repository
- You have the `jj-workspace` tool available

## Steps

### 1. Create a New Workspace

#### Option A: Using `fjj` (Recommended for Multi-Agent)

If you're using fjj for multi-agent workflows:

```bash
fjj feat/my-feature
```

This creates a workspace with conventional naming and auto-cds into it.

#### Option B: Using `jj-workspace`

For direct workspace creation:

```bash
jj-workspace create feat/my-feature
```

This creates a workspace named `feat/my-feature-YYYYMMDD-XXXX`.

#### Option C: From a Different Base

Create a workspace from a branch other than main:

```bash
jj-workspace create feat/my-feature develop
```

### 2. Navigate to the Workspace

If not automatically navigated:

```bash
cd ~/workspaces/feat-my-feature-20260115-a1b2
```

### 3. Start Working

Remember: always `jj new` before making changes:

```bash
jj new
# Make your changes...
```

### 4. Run System Switch from Workspace

When working in a jj workspace, you can still run the system switch command. The workspace-aware switch automatically detects you're in a workspace and runs from the main repo root while using your workspace's commit:

```bash
# From any workspace directory
s
# or
switch
# or
devenv tasks run system:switch
```

**What happens:**
- Switch detects you're in a workspace (`fix-build`, `feat-auth`, etc.)
- Displays: `📁 JJ Workspace: fix-build`
- Displays: `Switch will run from: /path/to/main/repo`
- Runs the switch from the main repo root using your current jj commit

**Requirements:**
- Commit your changes first with `jj describe -m "message"`
- The switch uses your current jj commit, so uncommitted changes won't be included

**To test uncommitted changes before committing:**
```bash
./scripts/switch-workspace-override
```

This creates a temporary copy of your workspace changes and runs switch from there.

### 4. Create a Bookmark and PR

```bash
jj-pr feat my-feature "Add new feature"
```

### 5. List All Workspaces

See all your workspaces:

```bash
jj-workspace list
```

Or with fjj:

```bash
fjj --list
```

### 6. Check Workspace Status

See what's happening in all workspaces:

```bash
jj-workspace status
```

### 7. Clean Up Finished Work

Remove merged or closed workspaces:

```bash
fjj --clean
```

Or manually remove a specific workspace:

```bash
jj-workspace remove feat-my-feature-20260115-a1b2
```

## Workspace Naming Convention

Workspaces follow the pattern: `<type>/<topic>-<date>-<id>`

Examples:
- `feat/user-auth-20260115-a1b2`
- `fix/login-bug-20260115-b3c4`
- `chore/update-deps-20260115-d5e6`

Types:
- `feat/` - New features
- `fix/` - Bug fixes
- `hotfix/` - Urgent fixes
- `chore/` - Maintenance tasks
- `release/` - Release preparation

## Session-Based Fast Sync

Enable fast sync for active workspaces (syncs every 5 minutes instead of hourly):

```bash
# Start a session
jj-workspace-session start

# Check session status
jj-workspace-session status

# Sync manually (also resets TTL)
jj-workspace-session sync

# End session
jj-workspace-session stop
```

Sessions automatically expire after 30 minutes of inactivity.

## Workspace Directory Structure

```
~/workspaces/
├── feat-auth-20260115-a1b2/          # Your workspace
│   ├── .jj/                          # Points to parent repo
│   └── .git -> /srv/github/...       # Symlink to parent git
├── fix-bug-20260115-b3c4/
└── ...
```

## Best Practices

1. **One feature per workspace** - Keep work isolated
2. **Use conventional naming** - Makes workspaces easy to identify
3. **Clean up regularly** - Run `fjj --clean` to remove merged workspaces
4. **Start sessions for active work** - Enables fast sync
5. **Don't commit in mirror** - Always work in workspaces

## Troubleshooting

### "Workspace already exists"

Use a different name or remove the existing one:

```bash
jj-workspace remove feat-my-feature-20260115-a1b2
```

### "Can't find workspace"

List all workspaces:

```bash
jj-workspace list
```

### "Session not found"

Check if `jj-workspace-session` is installed:

```bash
which jj-workspace-session
```

If not found, you may need to install the jj skill.

## Next Steps

- [Create a PR from workspace](./create-pr-with-jj.md)
- [Create stacked PRs](./create-stacked-prs.md)
- [Sync with main](./sync-with-main.md)

## See Also

- [JJ Commands Reference](../reference/jj-commands.md)
- [JJ Mental Model](../explanation/jj-mental-model.md)
- [Yaks in Workspaces](../explanation/yaks-workspaces.md)
