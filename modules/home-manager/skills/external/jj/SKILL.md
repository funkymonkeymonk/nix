---
name: jj
description: Use Jujutsu (jj) for version control. Covers workflow, commits, bookmarks, pushing to GitHub, absorb, squash, stacked PRs, and workspaces for multi-project isolation. Use when working with jj, creating commits, pushing changes, or managing version control.
---

# Jujutsu (jj) Version Control

## The Key Mental Model

**In jj, the working copy IS a commit.** This is fundamentally different from Git where you stage changes then commit. In jj, you're always working inside a commit.

This means:

- Changes you make are immediately part of the current commit
- You should start new work in a fresh commit (so you can squash it later)
- There's no staging area - your working directory is the commit

## Core Workflow

### Always Start with `jj status`

Before any operation, check your state:

```bash
jj status
```

- "Working copy is clean" = you're in an empty commit, ready to work
- Shows file changes = current commit has work in it
- Shows description = current commit is already described

### The Basic Pattern

```bash
# 1. Create a new commit BEFORE starting work
jj new

# 2. Make your changes (edit files)

# 3. Describe what you did
jj describe -m "Add user authentication"

# 4. Create a new commit for the next task
jj new

# Repeat
```

**Why `jj new` before work?** If you work directly in a described commit, those changes get mixed in. Then you have to split them later. Starting fresh means you can always squash back if needed.

### Common Commands

```bash
jj status          # Check current state - ALWAYS run first
jj log             # View commit history
jj diff            # See changes in current commit
jj describe -m ""  # Set/update commit message
jj new             # Create new empty commit
jj squash          # Move current changes into parent commit
jj absorb          # Auto-distribute changes to ancestor commits
```

## Bookmarks (Not Branches)

jj uses "bookmarks" instead of Git branches. Key differences:

- Bookmarks are just labels pointing to commits
- They don't automatically advance when you commit
- You can have commits without any bookmark

```bash
jj bookmark list              # List all bookmarks
jj bookmark set foo -r @      # Create/move bookmark to current commit
jj bookmark delete foo        # Delete a bookmark
```

## Pushing to GitHub

### First Push (New PR)

Use `--change` (`-c`) to auto-create a bookmark and push:

```bash
# Push current commit, auto-generates bookmark name
jj git push -c @

# Push parent of working copy (common when @ is empty)
jj git push -c @-
```

This creates a bookmark with an auto-generated name like `push-abcdefgh` and pushes it.

### Subsequent Pushes (Same PR)

Once a bookmark exists and tracks the remote, just push:

```bash
jj git push
```

jj knows which bookmarks have changed and pushes them. Force push is automatic when history rewrites.

### Creating the PR

```bash
# Get the bookmark name from jj log or the push output
jj log -r @ --no-graph

# Create PR with gh CLI (must specify --head since gh uses git)
gh pr create --head push-abcdefgh
```

## Making More Changes to a PR

When you need to update an existing PR:

```bash
# 1. Create new commit on top of the PR commit
jj new

# 2. Make your changes

# 3. Fold changes back into the PR commit
jj squash          # Moves all changes to parent

# 4. Push the update
jj git push
```

**Never work directly in the PR commit.** Always `jj new` first, then squash back.

## Squash vs Absorb

### `jj squash` - When You Know Where It Goes

Moves changes from current commit into parent:

```bash
jj squash                    # All changes to parent
jj squash file.rs            # Only specific files
jj squash --into <commit>    # Into a specific commit (not just parent)
```

### `jj absorb` - Auto-Distribute to Ancestors

Analyzes each changed line and moves it to the ancestor commit that last modified that line:

```bash
jj absorb
```

**Best for stacked PRs**: When you have commits A → B → C and fix things that belong in different commits, `jj absorb` figures out where each change should go.

Try `jj absorb` first. If it can't figure out where something goes (new lines, ambiguous context), use `jj squash` manually.

## Stacked PRs Workflow

When working on multiple dependent PRs:

```bash
# Create stack: each commit = one PR
jj new main
# work on feature A
jj describe -m "Feature A"
jj git push -c @

jj new
# work on feature B (depends on A)
jj describe -m "Feature B"
jj git push -c @

# Continue stacking...
```

### After a PR Merges

When a PR in the middle of the stack merges:

```bash
# 1. Update the next PR's base branch on GitHub
gh pr edit <PR_NUMBER> --base main

# 2. Fetch the new main
jj git fetch

# 3. Rebase the remaining stack onto main
jj rebase -r <first-remaining-commit> -d main

# 4. Push all updated branches
jj git push --all
```

The `*` mark in `jj log` indicates bookmarks that need pushing.

## Editing Earlier Commits

Need to modify a commit that has descendants?

```bash
# Switch working copy to that commit
jj edit <commit-id>

# Make changes (they go directly into that commit)

# Return to where you were
jj edit @

# Descendants are automatically rebased
jj git push --all
```

## Splitting Commits

When a commit has changes that should be separate:

```bash
# Interactive split
jj split

# Non-interactive: specify files for first commit
JJ_EDITOR=true jj split -m "First commit message" file1.rs file2.rs
# Remaining files stay in second commit
jj describe -m "Second commit message"
```

## Workspaces (Multi-Project Isolation)

Workspaces let you work on multiple independent features in the same repo without context pollution. Each workspace has its own working copy and working-copy commit, but shares the repo's history, bookmarks, and remote connections.

**Why use workspaces for agents?**

- **Context isolation**: Each workspace sees only its own files, limiting token usage
- **No permission issues**: Workspaces are local - no git auth or GitHub tokens needed
- **Shared history**: All workspaces see the same commits, bookmarks, and PRs
- **Independent builds**: Run tests in one workspace while coding in another

### Creating a Workspace

```bash
# From your main repo directory, create workspace for a specific feature
jj workspace add ./workspaces/feature-auth

# Start work from a specific commit (e.g., main)
jj workspace add ./workspaces/api-refactor -r main

# Create workspace with empty sparse patterns (minimal checkout)
jj workspace add ./workspaces/docs --sparse-patterns=empty
```

The workspace name defaults to the directory basename (e.g., `feature-auth`).

**Important**: Add `workspaces/` to your `.gitignore` to prevent tracking workspace directories.

### Listing Workspaces

```bash
jj workspace list
```

In `jj log`, workspace indicators show which workspace owns each working-copy commit:

```
@      abc123   feature-auth@    (empty) Working copy
|  @   def456   api-refactor@    (empty) Working copy
| /
o      789xyz   main             "Latest release"
```

### Workflow: Agent Per Workspace

For AI agents working on multiple tasks:

```bash
# 1. Create isolated workspace for each task
jj workspace add ./workspaces/task-1 -r main
jj workspace add ./workspaces/task-2 -r main

# 2. Agent works in task-1 directory
cd ./workspaces/task-1
jj new
# ... make changes ...
jj describe -m "Implement feature X"
jj git push -c @-

# 3. Switch to task-2 (different directory, different context)
cd ../task-2
jj new
# ... different changes ...
jj describe -m "Fix bug Y"
jj git push -c @-

# 4. Both PRs visible from either workspace
gh pr list  # Works from any workspace
```

### Rebasing Across Workspaces

Since all workspaces share the repo, rebase operations affect all:

```bash
# From any workspace, fetch updates
jj git fetch

# Rebase a commit (affects all workspaces that descend from it)
jj rebase -r <commit> -d main

# Push all changed bookmarks (from any workspace)
jj git push --all
```

If a workspace's working-copy commit gets rebased from another workspace, it becomes "stale":

```bash
# In the affected workspace, update to latest
jj workspace update-stale
```

### PR Management from Any Workspace

GitHub CLI works identically from any workspace since they share the `.git` directory:

```bash
# Create PR (works from any workspace)
jj git push -c @-
gh pr create --head push-abcdefgh

# List all PRs
gh pr list

# Check PR status
gh pr view <number>

# Merge a PR (triggers CI, merges on GitHub)
gh pr merge <number>
```

### Sparse Patterns for Focused Work

Limit which files appear in a workspace to reduce agent context:

```bash
# Create workspace with only specific directories
jj workspace add ./workspaces/backend
cd ./workspaces/backend
jj sparse set --add 'src/backend/**' --add 'tests/backend/**'

# Or start empty and add incrementally
jj workspace add ./workspaces/minimal --sparse-patterns=empty
cd ./workspaces/minimal
jj sparse set --add 'src/api/endpoints.rs'
```

### Cleaning Up Workspaces

```bash
# Remove a workspace (keeps its commits, just detaches working copy)
jj workspace forget <workspace-name>

# Then delete the directory manually
rm -rf ./workspaces/<workspace-name>
```

### Common Workspace Commands

```bash
jj workspace list              # Show all workspaces
jj workspace add <path>        # Create new workspace
jj workspace add <path> -r @   # New workspace starting at current commit
jj workspace forget <name>     # Stop tracking workspace
jj workspace update-stale      # Sync after external rebase
jj workspace root              # Show workspace root directory
jj sparse list                 # Show current sparse patterns
jj sparse set --add 'path/**'  # Add paths to sparse checkout
jj sparse reset                # Reset to full checkout
```

### Workspace Naming Conventions

For multi-agent or multi-task setups, use `./workspaces/` subdirectory:

```
myrepo/
├── workspaces/          # Add to .gitignore
│   ├── feature-foo/     # Feature work
│   ├── bugfix-bar/      # Bug fix
│   ├── review-123/      # PR review workspace
│   └── experiment/      # Throwaway experiments
├── src/
└── ...
```

## Undo

Made a mistake? jj tracks all operations:

```bash
jj undo              # Undo last operation
jj op log            # View operation history
jj op restore <id>   # Restore to specific operation
```

## Common Mistakes

### Working in a Described Commit

**Wrong:**

```bash
jj describe -m "Feature A"
# ... keep making changes in same commit ...
# Now Feature A commit has unrelated stuff mixed in
```

**Right:**

```bash
jj describe -m "Feature A"
jj new                      # Start fresh for next work
# ... make changes ...
jj squash                   # If changes belong in Feature A
```

### Forgetting `--allow-new` on First Push

```bash
# First time pushing a bookmark to a new remote
jj git push --bookmark main --allow-new
```

After the bookmark exists on the remote, you don't need this flag.

### Pushing a New Commit as a New PR

**Wrong:**

```bash
jj new
# ... changes for existing PR ...
jj git push -c @            # Creates NEW bookmark/PR!
```

**Right:**

```bash
jj new
# ... changes for existing PR ...
jj squash                   # Fold into existing PR commit
jj git push                 # Updates existing bookmark
```
