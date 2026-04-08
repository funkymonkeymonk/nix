---
title: "Sync with Main Branch"
description: "How to keep your work up-to-date with the main branch"
type: how-to
audience: developer
last-reviewed: 2026-04-07
---

# How to Sync with Main Branch

This guide shows you how to update your workspace with the latest changes from the main branch.

## Goal

Fetch changes from the remote main branch and rebase your work on top.

## Prerequisites

- You're in a jj repository with a remote configured
- You have commits that may need rebasing

## Steps

### 1. Choose Your Method

#### Option A: Using `jj-sync` (Recommended)

The easiest way to sync:

```bash
jj-sync
```

To sync against a different base branch:

```bash
jj-sync develop
```

#### Option B: Manual Steps

If you prefer manual control:

```bash
# Fetch latest changes
jj git fetch

# Rebase your current commit onto main
jj rebase -r @ -d main

# Push if you have a bookmark
jj git push
```

### 2. Resolve Conflicts (If Any)

If there are conflicts, jj will pause and show you the conflicted files:

```bash
jj status
```

Edit the conflicted files to resolve conflicts. Then:

```bash
jj resolve
```

### 3. Verify the Sync

Check your new position:

```bash
jj log
```

You should see your commits on top of the latest main.

## Automatic Sync

Enable auto-sync to keep your mirrors updated automatically:

### 1. Create `.jj-autosync` File

In your repository root:

```bash
cat > .jj-autosync << 'EOF'
enabled=true
main=main
fast_sync=true
EOF
```

### 2. Commit the Config

```bash
jj describe -m "chore: Enable auto-sync"
jj git push
```

### 3. Start a Session (for 5-minute sync)

```bash
jj-workspace-session start
```

Now your repository will sync every 5 minutes during active sessions.

## Sync Modes

| Mode | Frequency | Command |
|------|-----------|---------|
| Hourly | Every hour | Enabled by `.jj-autosync` |
| Fast (Session) | Every 5 min | `jj-workspace-session start` |
| Manual | On demand | `jj-sync` or `jj git fetch` |

## Troubleshooting

### "Already up to date"

Your branch is already synced. No action needed.

### "Merge conflicts"

1. Edit conflicted files
2. Mark resolved with `jj resolve`
3. Continue with `jj git push`

### "Divergent changes"

If you've pushed and someone else pushed too:

```bash
jj git fetch
jj rebase -r @ -d main
jj git push --bookmark <name>
```

## Next Steps

- [Create a PR](./create-pr-with-jj.md)
- [Update an existing PR](./update-existing-pr.md)
- [Use workspaces for isolation](./use-workspaces.md)

## See Also

- [JJ Commands Reference](../reference/jj-commands.md)
- [JJ Mental Model](../explanation/jj-mental-model.md)
