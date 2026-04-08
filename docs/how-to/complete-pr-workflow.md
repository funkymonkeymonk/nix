---
title: "Complete PR Workflow"
description: "End-to-end guide for completing a PR from start to merge"
type: how-to
audience: developer
last-reviewed: 2026-04-07
---

# How to Complete a PR Workflow

This guide shows the complete workflow from creating a PR through merging it, using jj tools.

## Goal

Complete the entire PR lifecycle: create, monitor CI, and merge.

## Prerequisites

- You have changes ready to push
- CI is configured on your repository
- You have merge permissions

## Steps

### Option A: Using `jj-finish` (All-in-One)

The `jj-finish` command orchestrates the entire workflow:

```bash
# Basic: Push, create PR, watch CI
jj-finish

# With auto-merge prompt
jj-finish --merge

# With limited retries
jj-finish --merge --max-retries 3
```

This runs:
1. `jj-push` - Push your changes
2. `jj-pr` - Create PR if needed
3. `watch-ci-jobs` - Monitor CI until completion
4. `jj-pr-merge` - Prompt to merge (if --merge flag)

### Option B: Step-by-Step

If you prefer manual control:

#### Step 1: Push Your Changes

```bash
jj-pr feat my-feature "Add user authentication"
```

Note the PR URL that gets printed.

#### Step 2: Monitor CI

Watch CI checks until they complete:

```bash
# If you know the PR number
watch-ci-jobs 123

# Or check via GitHub
gh pr checks --watch
```

#### Step 3: Fix Failures (If Needed)

If CI fails:

```bash
# Make fixes
jj new
echo "fix" >> file.txt

# Update PR
jj-update "fix: Address CI failures"

# Re-watch CI
watch-ci-jobs 123
```

Repeat until CI passes.

#### Step 4: Merge the PR

```bash
jj-pr-merge --method squash feat/my-feature
```

Methods:
- `--method squash` - Squash all commits (recommended)
- `--method merge` - Create a merge commit
- `--method rebase` - Rebase and merge

## Handling CI Failures

When `jj-finish` encounters CI failures:

1. **It pauses** - Doesn't give up, waits for you
2. **Shows failed checks** - Lists what's failing
3. **Prompts for fixes** - Waits for your input
4. **Auto-retries** - Up to 5 times (configurable with `--max-retries`)

Example interaction:

```
❌ CI checks failed!
Failed checks:
  - test-unit: failure
  - lint: failure

Fix issues and press Enter to retry...
Attempts remaining: 4
```

After fixing:

```bash
# Your fixes...
jj-update "fix: Resolve CI issues"
# Press Enter in the jj-finish window
```

## Dry Run Mode

Preview what `jj-finish` would do without executing:

```bash
jj-finish --dry-run
```

Useful for:
- Verifying configuration
- Understanding the workflow
- Testing in new repositories

## Retrying Failed PRs

If a PR is already created but CI failed:

```bash
# Navigate to workspace
cd ~/workspaces/feat-my-feature-...

# Make fixes
jj new
# ... edit files ...

# Update and finish
jj-update "fix: Address review comments"
jj-finish --merge
```

## After Merging

### 1. Clean Up

Remove the merged workspace:

```bash
fjj --clean
```

Or manually:

```bash
jj-workspace remove feat-my-feature-YYYYMMDD-XXXX
```

### 2. Sync Main

Update your main branch:

```bash
jj-sync
```

### 3. Start New Work

Create a fresh workspace:

```bash
fjj feat/next-feature
```

## Troubleshooting

### "No bookmark found"

Create a bookmark first:

```bash
jj bookmark set feat/my-feature -r @
```

### "CI never completes"

Some repositories don't have CI configured. Use:

```bash
jj-pr-merge --method squash feat/my-feature
```

Directly after pushing.

### "Merge conflicts on main"

Rebase your PR:

```bash
jj-sync
jj-update "rebase: Update with main"
```

Then retry `jj-finish`.

## Next Steps

- [Create stacked PRs](./create-stacked-prs.md)
- [Use workspaces](./use-workspaces.md)
- [Configure auto-sync](./sync-with-main.md#automatic-sync)

## See Also

- [JJ Commands Reference](../reference/jj-commands.md)
- [Update Existing PR](./update-existing-pr.md)
