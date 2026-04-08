---
title: "Getting Started with Jujutsu (jj)"
description: "Learn the basics of jj version control and create your first PR"
type: tutorial
audience: developer
last-reviewed: 2026-04-07
---

# Getting Started with Jujutsu (jj)

In this tutorial, you will learn the fundamentals of Jujutsu (jj) version control and complete your first pull request workflow. By the end, you'll understand the unique jj mental model and be able to confidently manage your code changes.

## What You'll Learn

- The jj "working copy as commit" mental model
- How to create and manage changes
- Creating and updating pull requests
- Using workspaces for isolated development

## Prerequisites

- A GitHub account with access to a repository
- The `jj` skill installed (provides workflow tools)
- GitHub CLI (`gh`) authenticated

## The jj Mental Model

Unlike git, **in jj, your working copy IS a commit**. There's no staging area. When you edit files, you're directly modifying the current commit.

This means:
- No `git add` step needed
- Changes are automatically tracked
- You describe commits when ready, not when creating them

## Step 1: Check Your Environment

First, verify everything is set up correctly:

```bash
jj status
```

You should see the current repository state. If you're not in a jj repository, navigate to one or initialize jj in a git repo with `jj git init --colocate`.

## Step 2: Start a New Commit

**Important**: Always create a new commit before making changes. This keeps your work isolated.

```bash
jj new
```

You now have an empty commit ready for your changes.

## Step 3: Make Some Changes

Edit any file in your project. For example, let's add a comment to a file:

```bash
echo "# TODO: Add feature X" >> README.md
```

Check the status:

```bash
jj status
```

Notice how jj shows your changes are already part of the current commit.

## Step 4: View Your Changes

See what you've changed:

```bash
jj diff
```

This shows the diff for your current commit, just like `git diff` but without staging.

## Step 5: Describe Your Commit

When you're happy with your changes, describe them:

```bash
jj describe -m "docs: Add TODO comment to README"
```

Your commit now has a message. The working copy remains editable until you create a new commit.

## Step 6: Create a Bookmark (Branch)

To push to GitHub, you need a bookmark (jj's term for a branch):

```bash
jj bookmark set feat/my-first-change -r @
```

This creates a bookmark named `feat/my-first-change` pointing at your current commit (`@`).

## Step 7: Push and Create a PR

Push your bookmark to GitHub and create a pull request:

```bash
jj git push --bookmark feat/my-first-change --allow-new
gh pr create --head feat/my-first-change --title "docs: Add TODO comment" --fill
```

Or use the convenient `jj-pr` tool:

```bash
jj-pr feat my-first-change "docs: Add TODO comment to README"
```

## Step 8: Verify Your PR

Open the PR URL shown in the output and verify:
- The changes look correct
- The commit message is descriptive
- CI checks are running

## Step 9: Update Your PR (Optional)

If you need to make changes after creating the PR:

```bash
# Make more edits
echo "# Another change" >> README.md

# Squash changes into the existing commit
jj squash

# Push the update
jj git push --bookmark feat/my-first-change
```

Or use the `jj-update` tool:

```bash
jj-update "docs: Updated with additional changes"
```

## Step 10: Complete the Workflow

When your PR is approved and CI passes, merge it:

```bash
jj-finish --merge
```

This will:
1. Verify CI passed
2. Prompt you to merge
3. Clean up after merge

## Congratulations!

You've completed your first jj workflow. You've learned:

- ✅ `jj new` creates a new commit
- ✅ Changes are automatically tracked (no staging)
- ✅ `jj describe` sets the commit message
- ✅ Bookmarks replace branches
- ✅ `jj squash` folds changes into parent commits

## Next Steps

- **Learn more commands**: See [JJ Commands Reference](../reference/jj-commands.md)
- **Create stacked PRs**: See [How to Create Stacked PRs](../how-to/create-stacked-prs.md)
- **Use workspaces**: See [How to Use Workspaces](../how-to/use-workspaces.md)
- **Understand the mental model**: See [JJ Mental Model](../explanation/jj-mental-model.md)

## Quick Reference

| Task | Command |
|------|---------|
| Start new work | `jj new` |
| Check status | `jj status` |
| See changes | `jj diff` |
| Set commit message | `jj describe -m "msg"` |
| Create bookmark | `jj bookmark set feat/name -r @` |
| Push bookmark | `jj git push --bookmark feat/name --allow-new` |
| Update PR | `jj squash && jj git push` |

## Common Mistakes to Avoid

1. **Forgetting `jj new`**: Always run this before making changes
2. **Creating new bookmarks for updates**: Use `jj squash` instead of creating new bookmarks
3. **Forgetting `--allow-new`**: Required the first time you push a bookmark

> 💡 **Tip**: Run `jj status` frequently to stay aware of your current state.
