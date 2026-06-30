---
title: "Update an Existing PR"
description: "How to make changes to a pull request you've already created"
type: how-to
audience: developer
last-reviewed: 2026-04-07
---

# How to Update an Existing PR

This guide shows you how to make additional changes to a pull request that has already been created.

## Goal

Add changes to an existing PR without creating a new one.

## Prerequisites

- You have an open PR
- You're in the same workspace where the PR was created

## Steps

### 1. Ensure You're on the PR Commit

Check your current position:

```bash
jj status
```

You should be on the commit with your bookmark. If not, navigate to it:

```bash
jj new <bookmark-name>
```

### 2. Make Your Changes

Edit files as needed. Remember, in jj your working copy IS the commit, so changes are automatically tracked.

### 3. Choose Your Method

#### Option A: Using `jj-update` (Recommended)

The simplest approach:

```bash
jj-update
```

To also update the commit message:

```bash
jj-update "feat: Add authentication with OAuth support"
```

#### Option B: Manual Steps

For more control:

```bash
# Squash changes into the parent commit
jj squash

# Update the commit message if needed
jj describe -m "feat: Updated authentication with OAuth"

# Push the update
jj git push --bookmark feat/user-auth
```

### 4. Verify the Update

Check that the PR was updated:

```bash
gh pr view feat/user-auth
```

## Important: Don't Create a New Bookmark

**Common mistake**: Creating a new bookmark for updates creates a NEW PR instead of updating the existing one.

❌ Wrong:
```bash
jj bookmark set feat/user-auth-v2 -r @  # Creates new PR!
```

✅ Correct:
```bash
jj squash && jj git push  # Updates existing PR
```

## Squash vs New Commit

Use `jj squash` to fold changes into the existing commit. This keeps the PR history clean with a single commit.

If you want to keep changes separate (not recommended for PR updates):

```bash
jj describe -m "additional changes"
jj git push --bookmark feat/user-auth
```

## Troubleshooting

### "Bookmark not found"

List your bookmarks:

```bash
jj bookmark list
```

Then use the correct name.

### "Nothing to squash"

Make sure you have uncommitted changes:

```bash
jj diff
```

If empty, you need to make changes first.

## Next Steps

- [Create stacked PRs](./create-stacked-prs.md)
- [Sync with main branch](./sync-with-main.md)

## See Also

- [JJ Commands Reference](../reference/jj-commands.md)
