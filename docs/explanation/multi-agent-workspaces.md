---
title: "Multi-Agent Development with jj Workspaces"
description: "Run multiple agents on different branches in the same repo simultaneously"
type: tutorial
audience: developer
last-reviewed: 2026-04-14
---

# Multi-Agent Development with jj Workspaces

In this tutorial you'll set up a workflow where multiple agents (or you and an agent, or two terminal sessions) each work on separate branches in the same repo at the same time — without stepping on each other.

## What You'll Learn

- How jj workspaces give each agent its own working copy
- The commit-first rule: why Nix flakes require committed changes
- How to run `switch`, `build`, and `check` from a workspace
- How to coordinate agents with `yx` (yaks) so nobody duplicates work
- How to create PRs and clean up when you're done

## Prerequisites

- This repository cloned and `devenv shell` active
- `fjj` available (enabled by the developer role)
- Basic familiarity with jj ([Getting Started with jj](./jj-workflow.md))
- GitHub CLI (`gh`) authenticated

## The Key Concept: Nix Reads Git, Not Your Working Copy

This is the source of most workspace confusion:

> **Nix flakes evaluate from the git tree, not the filesystem.**

When you run `nix build .#something`, Nix reads files from what git knows about — not what's on disk. In a jj-colocated repo, jj automatically exports to git, but only for **committed** changes. This means:

1. You edit a file in your workspace
2. jj sees it immediately (the working copy is a commit)
3. But `nix build` does **not** see it until jj exports to git
4. And Nix resolves `.` to the **flake root**, which in a workspace points back to the parent repo

The workspace-aware shell functions (`s`, `switch`, `b`, `q`) handle this for you. But understanding *why* they exist will save you from confusion when things don't work.

## Step 1: Verify Your Setup

Enter the devenv shell and confirm the tools are available:

```bash
devenv shell

# Check tools
which fjj
which jj-workspace
which yx
```

If `fjj` isn't found, ensure your target has the `developer` role enabled.

## Step 2: Create the First Workspace

Imagine Agent A is going to work on a new feature. Create a workspace:

```bash
fjj feat/user-auth
```

**What happens:**
- A new directory is created under `~/workspaces/` (e.g., `feat-user-auth-20260414-a1b2`)
- jj creates a workspace pointing back to the main repo's `.jj/` store
- Your shell auto-cds into the new workspace
- A fast-sync session starts (syncs every 5 minutes)

Verify you're in a workspace:

```bash
jj workspace list
```

You'll see `default` (the main repo) and your new workspace.

## Step 3: Create a Second Workspace

Open a **second terminal** (or have a second agent start). From the main repo directory (not from inside the first workspace), create another workspace:

```bash
fjj fix/login-bug
```

Now you have two workspaces, each with their own working copy, each at a different point in the commit graph — but sharing the same underlying jj/git store.

```bash
jj workspace list
# default
# feat-user-auth-20260414-a1b2
# fix-login-bug-20260414-c3d4
```

## Step 4: The Commit-First Rule

This is the most important rule for Nix repos with jj:

> **Always `jj describe` your changes before running any Nix command.**

Here's what goes wrong if you don't:

```bash
# In workspace feat/user-auth
echo "test" >> modules/roles/base.nix

# This will NOT see your change:
nix build .#darwinConfigurations.your-host

# Nix reads from git HEAD, and jj hasn't exported yet
```

The correct workflow:

```bash
# 1. Make your changes
echo "test" >> modules/roles/base.nix

# 2. Describe the commit (jj already tracks the change — this sets the message
#    AND triggers a git export)
jj describe -m "feat: add test to base role"

# 3. NOW run nix commands — the workspace-aware functions handle the rest
s
```

**Why `jj describe` matters here:** When you describe a commit, jj exports it to git. The Nix flake can then see the changes through the git store. Without this step, your changes exist in jj's operation log but not in git's tree.

## Step 5: Running Nix Commands from a Workspace

When you enter `devenv shell` from a workspace, the shell detects it:

```
📁 JJ Workspace: feat-user-auth-20260414-a1b2
   Switch will run from: /Users/you/src/nix
```

The following commands are workspace-aware and Just Work:

| Command | What it does |
|---------|-------------|
| `s` or `switch` | System switch (rebuilds your config) |
| `b` | Build all configurations (dry-run) |
| `q` | Run all checks (lint + builds) |

These functions automatically `cd` to the main repo root in a subshell before running, so Nix finds the flake correctly. Your terminal stays in the workspace directory afterward.

### What about raw nix commands?

If you need to run `nix build` or `nix eval` directly, they won't work from a workspace directory:

```bash
# This WON'T work from a workspace:
nix build .#darwinConfigurations.your-host

# Do this instead — reference the repo root explicitly:
nix build /path/to/main/repo#darwinConfigurations.your-host

# Or use a subshell:
(cd /path/to/main/repo && nix build .#darwinConfigurations.your-host)
```

The workspace-aware `s`/`b`/`q` functions exist specifically so you don't have to think about this for common operations.

## Step 6: Working in Parallel

Now both workspaces are set up. Each agent works independently:

**Agent A** (in `feat/user-auth`):
```bash
# Make changes to modules/roles/developer.nix
jj describe -m "feat: add auth tooling to developer role"
s   # Test the switch — runs from repo root automatically
jj-pr feat user-auth "Add auth tooling to developer role"
```

**Agent B** (in `fix/login-bug`):
```bash
# Fix a bug in modules/common/shell.nix
jj describe -m "fix: correct shell initialization order"
q   # Run checks — runs from repo root automatically
jj-pr fix login-bug "Fix shell initialization order"
```

Because each workspace has its own working copy, there are no file-level conflicts during development. Conflicts only surface later at PR merge time — and jj handles those gracefully.

## Step 7: Coordinating with Yaks

When multiple agents are working simultaneously, you need a way to prevent them from picking up the same task. That's what `yx` (yaks) does — it's a shared task tracker that syncs via git refs.

### Map out the work

```bash
yx add "Improve login flow"
yx add "Add auth middleware" --under "Improve login flow"
yx add "Fix session timeout" --under "Improve login flow"
yx ls
```

### Claim a task before starting

Each agent follows the **claim protocol**:

```bash
# 1. Pull latest state
yx sync

# 2. Check the task isn't already claimed
yx show "Add auth middleware"
# State should be "ready", not "wip"

# 3. Claim it
yx start "Add auth middleware"

# 4. Push your claim so other agents see it
yx sync
```

If another agent runs `yx sync` and sees "Add auth middleware" is `wip`, they know to pick something else.

### Complete and hand off

```bash
# When done with a task
yx done "Add auth middleware"
yx sync
```

Children must be completed before parents. This naturally enforces dependency order across agents.

## Step 8: Creating PRs from Workspaces

From each workspace, create a PR using the helper scripts:

```bash
# Creates bookmark, pushes, opens PR
jj-pr feat user-auth "Add user authentication support"
```

Or manually:

```bash
jj bookmark set feat/user-auth -r @
jj git push --bookmark feat/user-auth
gh pr create --head feat/user-auth --fill
```

To update after review feedback:

```bash
# Make fixes in your workspace
jj squash    # Fold changes into the PR commit
jj git push  # Force-push is automatic with jj
```

## Step 9: Clean Up

When PRs are merged, clean up workspaces:

```bash
# Auto-remove workspaces whose PRs are merged or closed
fjj --clean

# Or remove a specific workspace
jj-workspace remove feat-user-auth-20260414-a1b2

# Check what's left
jj workspace list
```

## Putting It All Together

Here's the complete flow for two agents working in parallel:

```
Main repo (~/src/nix)
  │
  ├── Agent A: fjj feat/user-auth
  │     ├── yx sync && yx start "Add auth"    ← claim the task
  │     ├── (edit files)
  │     ├── jj describe -m "feat: add auth"   ← commit-first!
  │     ├── s                                  ← switch from repo root
  │     ├── jj-pr feat user-auth "Add auth"   ← open PR
  │     └── yx done "Add auth" && yx sync     ← release the task
  │
  └── Agent B: fjj fix/login-bug
        ├── yx sync && yx start "Fix login"   ← claim the task
        ├── (edit files)
        ├── jj describe -m "fix: login bug"   ← commit-first!
        ├── q                                  ← check from repo root
        ├── jj-pr fix login-bug "Fix login"   ← open PR
        └── yx done "Fix login" && yx sync    ← release the task
```

## Common Pitfalls

### "error: Path 'flake.nix' is not in the Nix store"

You ran a nix command from the workspace directory instead of the repo root. Use `s`/`b`/`q` or explicitly run from the repo root.

### "untracked files" error from Nix

You have changes that jj hasn't exported to git yet. Run `jj describe -m "wip"` to trigger an export, then retry.

### Switch builds old code

You forgot to commit before switching. The flake reads from git, so it sees whatever was last exported. Run `jj describe` to export your latest changes.

### Workspace shows "stale working copy"

Another workspace (or the main repo) modified a commit that your workspace depends on. Fix it:

```bash
jj workspace update-stale
```

### Parent commit has jj conflicts

jj stores conflicts differently than git. If a parent commit has unresolved conflicts, git can't read those files. Resolve them first:

```bash
jj new <conflicted-commit>
jj resolve
jj squash
```

Or rebase your workspace onto a clean commit.

## What You've Learned

| Concept | Key Takeaway |
|---------|-------------|
| Workspaces | Each agent gets its own working copy via `fjj` |
| Commit-first | Always `jj describe` before running Nix commands |
| Workspace-aware shell | `s`, `b`, `q` auto-detect workspaces and run from repo root |
| Raw nix commands | Must be run from the repo root, not the workspace |
| Yaks coordination | `yx start` + `yx sync` prevents duplicate work |
| Cleanup | `fjj --clean` removes merged workspaces |

## What's Next

- **[How to Use Workspaces](../how-to/use-workspaces.md)** — reference for all workspace commands
- **[Yaks in Workspaces](../explanation/yaks-workspaces.md)** — why yaks data is shared across workspaces
- **[Your First Yak](./yak-shaving.md)** — deeper tutorial on the yak task tracker
- **[JJ Commands Reference](../reference/jj-commands.md)** — every jj command and alias
