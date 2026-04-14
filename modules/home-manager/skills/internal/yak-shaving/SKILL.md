---
name: yak-shaving
description: Use when tracking, planning, or implementing work using yx (yaks) in a repository with jj workspaces, or when multiple agents need to coordinate on shared tasks
---

# Yak Shaving with yx + jj Workspaces

## Overview

Use `yx` (yaks) for shared task tracking and `jj` workspaces for isolated implementation. Yaks syncs via hidden git refs (`refs/notes/yaks`) using CRDTs -- multiple agents update simultaneously with zero conflicts.

**Key mental model:** `yx` owns **what** to do. `jj` owns **where** to do it. They share the same git repo but operate independently.

## Quick Reference

| Action | Command |
|--------|---------|
| List yaks | `yx ls` (alias: `yl`) |
| List all (inc. done) | `yx ls --all` (alias: `yla`) |
| Add yak | `yx add "task name"` (alias: `ya`) |
| Add child yak | `yx add "child" --under "parent"` |
| Show details | `yx show "task name"` |
| Claim yak | `yx start "task name"` |
| Mark done | `yx done "task name"` (alias: `yd`) |
| Set/read context | `yx context "task name"` (stdin) / `yx context --show "task name"` |
| Custom fields | `yx field "task name" progress` (stdin) / `yx field --show "task name" progress` |
| Sync with remote | `yx sync` (alias: `ys`) |
| Move yak | `yx move "yak" --under "parent"` / `yx move "yak" --to-root` |
| Remove yak | `yx rm "task name"` |
| Prune done yaks | `yx prune` |
| JSON output | `yx ls --format json` / `yx show "name" --format json` |

## The Claim Protocol

**ALWAYS follow this sequence before starting work on a yak:**

```bash
yx sync                    # 1. Get latest state from other agents
yx show "yak name"         # 2. Check state -- if wip, pick another
yx start "yak name"        # 3. Claim it (sets state to wip)
yx sync                    # 4. Push your claim so others see it
```

**Never skip sync.** Without it, two agents can claim the same yak simultaneously.

## Three Workflows

### /map -- Discover work structure

Use when: starting a new goal, need to find what blocks what.

**Core rule:** Approach, don't decompose. Ask "what would we try first?" not "what are all the pieces?"

```bash
yx add "goal name"
yx ls                              # THE IRON LAW: yx ls after EVERY yx add
yx add "blocker" --under "goal"    # Nesting = "goal is BLOCKED BY blocker"
yx ls                              # Always show the map
```

**Iron Law:** Run `yx ls` after every `yx add` or `yx move`. No exceptions.

**Scope first:** After adding the top-level goal, discuss scope with the human before adding children. Don't create yaks for everything you can think of.

**Nesting means dependency:** Children block parents. Work leaves first (deepest nodes), then their parents.

### /prepare -- Spec out a yak

Use when: yak exists but needs detail before implementation.

1. `yx show "yak"` -- read existing state
2. `yx start "yak"` -- claim it
3. Brainstorm spec with user, store as context:
   ```bash
   cat <<'EOF' | yx context "yak name"
   # Goal
   [What and why]
   # Acceptance Criteria
   - [ ] Criterion 1
   - [ ] Criterion 2
   EOF
   ```
4. Break into sub-yaks if too large (iron law applies)
5. Each sub-yak gets context with exact file paths and definition of done

### /work -- Implement a yak

**Use jj workspaces, NOT git worktrees.** This is the critical adaptation from upstream yaks.

#### Step 1: Claim

```bash
yx sync
yx show "yak name"               # Verify state is todo, not wip
yx start "yak name"
yx sync
```

#### Step 2: Create jj workspace

If `jj-workspace-session` is available (enables fast-sync every 5 min):
```bash
jj-workspace-session start chore/yak-slug
```

Otherwise, create manually:
```bash
jj workspace add --name chore-yak-slug .workspaces/chore-yak-slug
```

Naming convention: `<type>-<slug>` (`feat`, `fix`, `chore`, etc.). Workspaces go in `.workspaces/` relative to repo root.

#### Step 3: Implement in the workspace

```bash
# Work in the new workspace
# All changes are automatically in the jj working copy commit
jj describe -m "chore: implement the yak"
```

Follow the repo's commit-first workflow: describe changes with `jj describe`, then run nix checks.

#### Step 4: Store progress

```bash
echo "Implemented X, Y, Z. Tests pass." | yx field "yak name" progress
```

#### Step 5: Push and create PR

```bash
jj bookmark set chore/yak-slug -r @
jj git push --bookmark chore/yak-slug
gh pr create --title "chore: description" --body "..."
```

#### Step 6: Mark done and clean up

```bash
yx done "yak name"
yx sync
jj workspace remove chore-yak-slug
```

## Multi-Agent Coordination

All jj workspaces share the same underlying git repo, which means they share yaks data.

### Claiming prevents conflicts

- `yx sync` before claiming pulls others' claims
- `yx start` sets wip state
- `yx sync` after claiming pushes your claim
- Other agents see wip and skip that yak

### Workspace isolation

Each agent gets its own jj workspace at a different commit. No file-level conflicts during implementation. Conflicts only arise at PR merge time if agents modified the same files.

### @needs-human convention

When stuck or need a decision:
```bash
yx tag "yak name" @needs-human
cat <<'EOF' | yx context "yak name"
[existing context]

## Open Question
What should X do when Y happens?
EOF
yx sync
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using `git worktree` instead of `jj workspace` | Always use `jj workspace add` for isolation |
| Skipping `yx sync` before/after claiming | Sync is mandatory -- other agents can't see your claim without it |
| Not checking state before `yx start` | Always `yx show` first to verify it's not already wip |
| Workspace outside `.workspaces/` | Use `.workspaces/<name>` relative to repo root |
| Forgetting `yx ls` after adding yaks | Iron Law: `yx add` then `yx ls`, always |
| Touching `.yaks/` directory directly | Use `yx` CLI only -- never `rm`, `mkdir`, `cat` on `.yaks/` |
| Using `git commit` in a jj workspace | Use `jj describe` -- the working copy IS the commit |
| Not syncing yaks after marking done | Others won't see completion without `yx sync` |
