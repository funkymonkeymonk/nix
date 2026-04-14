---
title: "Create a PR with jj"
description: "Step-by-step guide to creating a pull request using Jujutsu"
type: how-to
audience: developer
last-reviewed: 2026-04-07
---

# How to Create a PR with jj

This guide shows you how to create a pull request using Jujutsu (jj) version control.

## Goal

Create and submit a pull request for your code changes using the jj workflow.

## Prerequisites

- You have changes ready to commit
- You're in a jj repository
- GitHub CLI (`gh`) is authenticated

## Steps

### 1. Ensure You're on a New Commit

If you haven't already, create a new commit for your work:

```bash
jj new
```

### 2. Make and Describe Your Changes

Make your code changes, then describe the commit:

```bash
jj describe -m "feat: Add user authentication"
```

### 3. Choose Your Method

#### Option A: Using `jj-pr` (Recommended)

The `jj-pr` tool handles the entire workflow:

```bash
jj-pr feat user-auth "Add user authentication flow"
```

Parameters:
- `feat` - The type (feat, fix, chore, hotfix, release)
- `user-auth` - Short description (kebab-case)
- `"Add user authentication flow"` - Commit message (optional, defaults to description)

#### Option B: Manual Steps

If you prefer manual control:

```bash
# Create bookmark
jj bookmark set feat/user-auth -r @

# Push to remote
jj git push --bookmark feat/user-auth

# Create PR
g h pr create --head feat/user-auth --fill
```

### 4. Verify the PR

Check that the PR was created successfully:

```bash
gh pr view feat/user-auth
```

## Conventional Branch Naming

Use these prefixes for your bookmarks:

| Prefix | Use For | Example |
|--------|---------|---------|
| `feat/` | New features | `feat/user-auth` |
| `fix/` | Bug fixes | `fix/null-pointer` |
| `hotfix/` | Urgent fixes | `hotfix/security-patch` |
| `chore/` | Maintenance | `chore/update-deps` |
| `release/` | Releases | `release/v1.2.0` |

## Troubleshooting

### "No changes in working copy"

You haven't described your commit yet:

```bash
jj describe -m "your message"
```

### "Bookmark already exists"

Use a different name or delete the old bookmark:

```bash
jj bookmark delete feat/user-auth
```

### "Failed to push"

Ensure the remote is configured and you have push access:

```bash
jj git remote list
```

## Next Steps

- [Update an existing PR](./update-existing-pr.md)
- [Create stacked PRs](./create-stacked-prs.md)
- [Complete PR workflow with jj-finish](./complete-pr-workflow.md)

## See Also

- [JJ Commands Reference](../reference/jj-commands.md)
- [JJ Mental Model](../explanation/jj-mental-model.md)
