---
title: "Create Stacked PRs"
description: "How to create dependent pull requests that build on each other"
type: how-to
audience: developer
last-reviewed: 2026-04-07
---

# How to Create Stacked PRs

This guide shows you how to create pull requests that depend on each other, allowing you to build features incrementally.

## Goal

Create a series of PRs where each one builds on the previous.

## Prerequisites

- You have an open PR already
- You want to create a PR that depends on it

## Steps

### 1. Create a Stacked PR

#### Option A: Using `jj-stack` (Recommended)

```bash
jj-stack feat api-endpoints "Add API endpoints for user management"
```

This automatically:
- Creates a new workspace on top of your current PR
- Sets the correct base branch
- Creates the PR with proper targeting

#### Option B: Manual Steps

```bash
# 1. Note your current bookmark
CURRENT_BOOKMARK=$(jj log -r @ --no-graph -T 'bookmarks' | head -1)

# 2. Create new commit on top
jj new

# 3. Make changes
# ... edit files ...

# 4. Describe and bookmark
jj describe -m "feat: Add API endpoints"
jj bookmark set feat/api-endpoints -r @

# 5. Push with correct base
jj git push --bookmark feat/api-endpoints --allow-new

# 6. Create PR targeting the first branch
g h pr create --base "$CURRENT_BOOKMARK" --head feat/api-endpoints --fill
```

### 2. Verify Stacking

Check that the second PR targets the first:

```bash
gh pr view feat/api-endpoints --json baseRefName
```

It should show your first bookmark (e.g., `feat/user-auth`).

### 3. Continue Stacking

You can keep stacking:

```bash
jj-stack feat frontend-ui "Add frontend UI components"
```

Now you have:
- PR #1: `feat/user-auth` → `main`
- PR #2: `feat/api-endpoints` → `feat/user-auth`
- PR #3: `feat/frontend-ui` → `feat/api-endpoints`

## Merging Stacked PRs

### Important: Merge in Order

Always merge from the bottom up:

1. Merge PR #1 (`feat/user-auth`)
2. GitHub automatically updates PR #2's base to `main`
3. Merge PR #2
4. GitHub updates PR #3's base to `main`
5. Merge PR #3

### Using `jj-finish`

```bash
# In first workspace
jj-finish --merge

# After first merges, move to second workspace
cd ../feat-api-endpoints-...
jj-finish --merge

# Continue with third...
```

## Handling Changes to Base PR

If you need to update the base PR:

```bash
# Go to base PR workspace
cd ../feat-user-auth-...

# Make changes
jj new
# ... edits ...
jj-update "fix: Address review comments"

# Go back to stacked PR
cd ../feat-api-endpoints-...

# Rebase onto updated base
jj-sync feat/user-auth
```

## Best Practices

### 1. Keep Stacks Short

Don't stack more than 3-4 PRs deep. Long chains become difficult to manage.

### 2. Independent Chunks

Each PR should be reviewable independently, even if it builds on previous work.

### 3. Clear Dependencies

PR descriptions should mention what they depend on:

```markdown
## Depends On
- #123 (Add user authentication)

## Changes
This PR adds API endpoints that use the auth from #123.
```

### 4. Fast Base PRs

Try to get base PRs merged quickly. Long-lived base PRs create stale stacks.

## Troubleshooting

### "Base branch not found"

Make sure the base PR's bookmark exists:

```bash
jj bookmark list
```

If it was deleted or renamed, recreate it:

```bash
jj bookmark set feat/user-auth -r <commit-id>
```

### "Merge conflicts after base PR merged"

After the base PR merges to main, rebase:

```bash
jj-sync
```

### "Stack too deep"

If you have 5+ PRs stacked, consider:
- Merging earlier PRs first
- Combining related changes
- Creating independent branches instead

## Alternative: Independent Branches

Instead of stacking, you can create independent PRs from main:

```bash
# First PR
fjj feat/part-one
jj-pr feat part-one "Part 1: Core infrastructure"

# Second PR (from main, not stacked)
fjj feat/part-two
jj-pr feat part-two "Part 2: Feature implementation"
```

Trade-offs:
- ✅ Can be reviewed and merged independently
- ❌ May have conflicts if they touch the same files
- ❌ Harder to test together

Choose based on your needs.

## Example Workflow

```bash
# Create base PR
fjj feat/auth-core
jj-pr feat auth-core "Add authentication core"

# Stack UI on top
jj-stack feat auth-ui "Add authentication UI"

# Stack API on top of UI
jj-stack feat auth-api "Add authentication API"

# Merge bottom-up
jj-finish --merge  # auth-core
jj-finish --merge  # auth-ui (now targeting main)
jj-finish --merge  # auth-api (now targeting main)

# Clean up
fjj --clean
```

## See Also

- [Create a PR](./create-pr-with-jj.md)
- [Complete PR Workflow](./complete-pr-workflow.md)
- [JJ Commands Reference](../reference/jj-commands.md)
