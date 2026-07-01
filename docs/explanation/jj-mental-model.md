---
title: "JJ Mental Model"
description: "Understanding how Jujutsu differs from git and why it works the way it does"
type: explanation
audience: developer
last-reviewed: 2026-04-07
---

# JJ Mental Model

Understanding the fundamental concepts behind Jujutsu (jj) and how they differ from traditional version control systems.

## The Core Principle: Working Copy IS a Commit

In jj, **your working copy is always a commit**. This is the single most important concept to internalize.

### Comparison with Git

**Git workflow:**
1. Edit files (working directory)
2. `git add` (stage changes)
3. `git commit` (create commit)

**jj workflow:**
1. Edit files (working copy commit)
2. `jj describe` (set message when ready)

There's no staging area because you're always editing the current commit.

### Why This Matters

- **No lost work**: Changes are automatically tracked
- **No staging mistakes**: Everything is part of the commit
- **Flexible commit timing**: Describe when ready, not when creating

## The Change ID vs Commit ID

jj has two identifiers for every commit:

### Change ID
- Stable across rebases and edits
- Used for tracking a logical change
- Format: Short hash like `knnqylxszwql`

### Commit ID
- Changes with every edit
- Git-compatible SHA
- Format: Full git hash

**When to use each:**
- Use **change IDs** for referencing your own work (stable)
- Use **commit IDs** for git compatibility (exact pointer)

## Bookmarks vs Branches

jj uses "bookmarks" instead of "branches":

### What's Different?

**Git branches:**
- Mutable pointers to commits
- Moving branch changes what's "current"

**jj bookmarks:**
- Mutable pointers to commits
- Separate from the commit itself
- Can be moved freely without affecting the change

### Practical Impact

```bash
# In git, you ARE on a branch
git checkout feature
# Now you're on "feature"

# In jj, you have a commit with optional bookmarks
jj bookmark set feature -r @
# The commit exists, bookmark points to it
```

The commit (`@`) exists independently of bookmarks.

## The @ Symbol

`@` is shorthand for "the current commit" (the working copy).

### Common Uses

```bash
jj log -r @              # Show current commit
jj bookmark set x -r @   # Point bookmark at current
jj diff -r @            # Diff current commit
```

Think of `@` as "here and now".

## Evolution, Not Mutation

jj tracks the **evolution** of changes, not just the final state.

### Operation Log

Every operation is recorded:

```bash
jj op log
```

Shows:
- When you created commits
- When you rebased
- When you described
- When you bookmarked

### Undo Any Operation

```bash
jj undo           # Undo last operation
jj op restore 5   # Restore to operation 5
```

This is more powerful than git's reflog because it understands semantic operations.

## Conflicts as First-Class

jj can represent conflicts directly in the commit graph.

### Conflict Storage

Unlike git's conflict markers, jj stores conflicts structurally:

```
Commit A
├── Our changes
├── Their changes
└── Base
```

This means:
- You can commit conflicts
- You can rebase conflicts
- You can resolve later

### Resolving

```bash
jj resolve          # Mark resolved
jj resolve --list   # See conflicts
```

## Colocation with Git

jj can work alongside git in the same repository.

### How It Works

- `.git/` - Git repository
- `.jj/` - jj repository data
- Both share the same files

### Why Colocate?

- **Compatibility**: Tools that expect git still work
- **Gradual adoption**: Use jj for some operations, git for others
- **GitHub integration**: PR workflows through git

### The Trade-off

jj stores extra metadata that git doesn't understand. Some git operations may confuse jj's view of history.

**Best practice**: Use jj for history manipulation, git for simple operations.

## Immutable Commits, Mutable Bookmarks

### Commits Don't Change

Once created, a commit's content is immutable. When you:
- Edit files → new commit
- Rebase → new commit
- Amend → new commit

### Bookmarks Move

Bookmarks are mutable pointers:

```bash
jj bookmark set feature -r @   # Points bookmark at @
jj new                         # @ moves forward
jj bookmark set feature -r @   # Move bookmark to new @
```

This separation allows flexible workflows.

## The Squash Operation

jj's `squash` is more powerful than git's squash.

### What It Does

Folds changes from a commit into its parent:

```
Before:
A -> B (changes) -> C (working copy)

After squash C into B:
A -> B' (changes + working copy)
```

### Why It's Useful

- Update PRs without creating new commits
- Clean up history
- Amend changes after the fact

### Comparison with Git

**Git:**
```bash
git add .
git commit --amend
```

**jj:**
```bash
jj squash
```

jj's version is more flexible because you can squash into any ancestor, not just the parent.

## Absorb: Automatic Distribution

`jj absorb` distributes changes to the commits that introduced the relevant lines.

### How It Works

1. You make a fix in the working copy
2. `jj absorb` finds which ancestor commit introduced each changed line
3. It squashes each change into the appropriate commit

### When to Use

- Fixing bugs found during review
- Addressing review comments
- Cleaning up before PR submission

### Example

```
A -> B -> C -> D (working copy with fixes)

jj absorb:
- Fix 1 → squashed into B
- Fix 2 → squashed into C
- Fix 3 → stays in D
```

## Workspaces: Isolated Views

jj workspaces allow multiple working directories sharing the same repository.

### Mental Model

Think of workspaces as "checkouts" that share history:

```
Repository
├── Workspace 1: feat/auth  (@1)
├── Workspace 2: fix/bug    (@2)
└── Workspace 3: main       (@3)
```

Each workspace has its own `@` (working copy).

### Why Use Workspaces?

- **Isolation**: Work on multiple features simultaneously
- **Clean main**: Keep main branch pristine
- **Parallel review**: Have different PRs checked out
- **Multi-agent**: Different agents can work independently

## Auto-Sync Design

The auto-sync system keeps mirrors updated automatically.

### Philosophy

- **Background operation**: Sync happens without interrupting work
- **Conflict avoidance**: Frequent syncs reduce merge conflicts
- **Session-aware**: Faster sync during active work

### Modes

| Mode | Frequency | Use Case |
|------|-----------|----------|
| Hourly | 1 hour | Background maintenance |
| Session | 5 minutes | Active development |
| Manual | On demand | Explicit control |

### Conflict Handling

Auto-sync only updates if there are no local changes. If you have uncommitted work, it waits.

## Comparison with Git

| Concept | Git | jj |
|---------|-----|-----|
| Working state | Working directory | Commit (@) |
| Staging | Required | None |
| Commits | Mutable with amend | Immutable, evolve |
| Branches | Mutable pointers | Bookmarks (separate) |
| History | Fixed | Mutable via operations |
| Undo | Reflog | Operation log |
| Conflicts | Must resolve immediately | Can commit and resolve later |
| Worktrees | Multiple checkouts | Native workspaces |

## Why jj?

### Advantages

1. **No staging area** - Faster workflow
2. **Immutable history** - Safer experimentation
3. **Operation log** - Comprehensive undo
4. **Conflict flexibility** - Resolve when ready
5. **Native workspaces** - Better isolation

### Trade-offs

1. **Learning curve** - Different mental model
2. **Tooling** - Less ecosystem than git
3. **GitHub** - Still need git for PRs
4. **New project** - Smaller community

## Recommended Reading

- [JJ Workflow guide](../how-to/jj-workflow.md) - Hands-on learning
- [How to Create a PR](../how-to/create-pr-with-jj.md) - Practical workflow
- [JJ Commands Reference](../reference/jj-commands.md) - Command details
