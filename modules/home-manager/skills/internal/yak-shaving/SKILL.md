---
name: yak-shaving
description: Use when tracking, planning, implementing, or reviewing work using yx (yaks) with the autonomous /shave loop, or when multiple agents need to coordinate on shared tasks
---

# Yak Shaving

## Overview

Use `yx` (yaks) for shared task tracking across agents and humans. Yaks syncs via hidden git refs (`refs/notes/yaks`) using CRDTs -- multiple agents update simultaneously with zero conflicts.

**Key mental model:** `yx` owns **what** to do. Everything else owns **how** to do it.

**Dependency model:** Use `## Prerequisites` in context for dependencies (not deep nesting). Keep yaks flat under a story. Children block parents. Work leaves first, then their parents. The `@blocked` tag prevents triage from picking blocked yaks.

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
| Tag management | `yx tag add/rm "task name" "@tag"` |
| Sync with remote | `yx sync` (alias: `ys`) |
| Move yak | `yx move "yak" --under "parent"` / `yx move "yak" --to-root` |
| Remove yak | `yx rm "task name"` |
| Prune done yaks | `yx prune` |
| JSON output | `yx ls --format json` / `yx show "name" --format json` |

## Dependency Model

Use flat hierarchies (story → tasks) with `## Prerequisites` in each task's context:

```
○ Story name  (top level)
  ├─ ○ Task A  (@blocked)  — has ## Prerequisites: Task B
  ├─ ○ Task B              — no prerequisites, actionable
  ╰─ ○ Task C  (@blocked)  — has ## Prerequisites: Task A
```

- **Story at top level**, all tasks as **flat children**
- Each task has `## Prerequisites` in its context listing dependencies
- Tasks with unmet prereqs get tagged `@blocked`
- When a task completes, remove `@blocked` from its dependents
- The triage script auto-resolves `## Prerequisites` — a yak is blocked if any prereq isn't `done`

**Context format:**
```markdown
## Prerequisites
- Task A must be done
```

**When completing a task that unblocks others:**
```bash
yx tag rm "Dependent Task" "@blocked"
yx sync
```

## The Claim Protocol

**ALWAYS follow this sequence before starting work on a yak:**

```bash
yx sync                    # 1. Get latest state from other agents
yx show "yak name"         # 2. Check state -- if wip, pick another
yx start "yak name"        # 3. Claim it (sets state to wip)
yx sync                    # 4. Push your claim so others see it
```

**Never skip sync.** Without it, two agents can claim the same yak simultaneously.

## Scripts

All scripts live in `scripts/` relative to this skill:

| Script | Purpose |
|--------|---------|
| `yak-triage.sh` | Find actionable (todo, leaf, unblocked) yaks |
| `yak-claim.sh "name"` | Safely claim a yak (sync → check → start → sync) |
| `yak-needs-refinement.sh "name"` | Test if yak has enough context to implement |
| `yak-worker-prompt.sh "name"` | Generate full subagent implementation prompt |
| `yak-mark-refinement.sh "name" "reason"` | Tag yak @needs-human with reason |

## Five Workflows

### /map -- Discover work structure

Use when: starting a new goal, need to find what blocks what.

**Core rule:** Approach, don't decompose. Ask "what would we try first?" not "what are all the pieces?"

```bash
yx add "goal name"
yx add "task" --under "goal"   # Flat children under story
yx tag add "task" "@blocked"   # If it depends on another task
yx ls                          # THE IRON LAW: yx ls after EVERY yx add
yx context "task"              # Add ## Prerequisites and acceptance criteria
```

**Iron Law:** Run `yx ls` after every `yx add` or `yx move`. No exceptions.

### /review -- Human-in-the-loop backlog refinement

Use when: a human wants to work through `@needs-human` yaks interactively.

**Step 1: Pick a topic cluster**
```bash
yx ls
```

**Step 2: For each yak — verify the code before deciding**
```bash
yx show "yak name"
grep -rn "<pattern>" modules/ targets/ os/
find . -name "<filename>" 2>/dev/null
```

**Step 3: Apply one of four verdicts**

| Verdict | When | Commands |
|---------|------|----------|
| **Delete** | Stale — problem no longer exists in code | `yx rm "yak name"` |
| **Close** | Policy already decided, no code to write | `yx done "yak name"` |
| **Unblock** | Problem is real and scope is clear | Add context + `yx tag rm "yak name" "@needs-human"` |
| **Keep** | Genuinely needs human input | Update context with _why_ it's blocked, leave tag |

**Step 4: Write full context before unblocking**
```bash
cat <<'EOF' | yx context "yak name"
# Goal
[What and why]

## Prerequisites
- [prerequisite task must be done]

# Acceptance Criteria
- [ ] Specific, verifiable outcome

# Files
- path/to/file.nix (what to change)
EOF

yx tag rm "yak name" "@needs-human"
```

### /prepare -- Spec out a yak

Use when: yak exists but needs detail before implementation.

1. `yx show "yak"` -- read existing state
2. `yx start "yak"` -- claim it
3. Brainstorm spec with user:
   ```bash
   cat <<'EOF' | yx context "yak name"
   # Goal
   [What and why]

   ## Prerequisites
   - [dependencies]

   # Acceptance Criteria
   - [ ] Criterion 1

   # Files
   - path/to/file.nix
   EOF
   ```
4. Break into sub-yaks if too large (iron law applies)
5. Each sub-yak gets context with exact file paths and definition of done

### /work -- Implement a yak

Use when: a yak is claimed and ready to implement.

```bash
yx sync
yx show "yak name"               # Verify state is todo
yx start "yak name"
yx sync
# Implement (TDD first)
echo "Progress notes" | yx field "yak name" progress
# Ship and mark done
yx done "yak name"
yx sync
```

### /shave -- Autonomous backlog processing

Use when: you want to autonomously work through the entire backlog.

**The /shave Loop:**
```
WHILE actionable yaks exist:
  1. yx sync                          — pull latest state
  2. yak-triage.sh                    — find actionable yaks
  3. FOR EACH batch of compatible yaks (no file conflicts):
     a. yak-needs-refinement.sh       — test clarity
        → unclear: yak-mark-refinement.sh, skip
        → clear:   yak-claim.sh, dispatch subagent
  4. WAIT for all subagents to complete
  5. On completion: remove @blocked from dependents
  6. yx sync                          — push done state
```

**Setup:**
```bash
SKILL_DIR="$HOME/.config/opencode/skills/yak-shaving/scripts"
```

**When completing a yak that unblocks others:**
```bash
yx done "completed yak"
yx tag rm "dependent yak" "@blocked"
yx sync
```

## TDD/BDD Requirements

Every subagent MUST follow this order — no exceptions:

```
RED:   Write failing test first
         → Nix: pkgs.runCommand that exits 1 without the fix
         → Shell: bash test with mock structures
         → CI: check verifying file structure
GREEN: Write minimal implementation to pass the test
REFACTOR: Clean up while keeping tests green
```

Acceptance criteria in yak context → test cases. Each `- [ ] criterion` becomes a test assertion.

**BDD style:** Tests describe outcomes, not mechanisms.
```nix
# ❌ Mechanism: "module sets this attribute"
if config.services.foo.package == pkgs.foo
# ✅ Outcome: "foo service uses the configured package"
if config.services.foo.package == configuredPkg
```

## Deciding: Implement vs Refine

```
Has context?           → No  → Mark @needs-human: "No context defined"
Has acceptance criteria? → No  → Mark @needs-human: "No checkboxes/criteria"
Has specific files?    → No  → Mark @needs-human: "No file paths mentioned"
All yes?               → Implement
```

Use `yak-needs-refinement.sh` to automate this check.

## Parallelism Rules

**Safe to parallelize:** Yaks touching different files/modules (checked via context file paths)

**Must serialize:**
- Two yaks editing the same Nix file
- Yaks that both modify `flake.nix` or `tests/default.nix` (high conflict surface)

**Practical limit:** 2-3 parallel subagents.

## PR Workflow per Yak

Each subagent runs the full cycle:

```bash
# 1. Workspace (isolated, off current main)
jj git fetch
jj workspace add --name <type>-<slug> .workspaces/<type>-<slug>

# 2. Implement (TDD first)

# 3. Validate
devenv tasks run check:lint
devenv tasks run test:darwin-eval
git add -A && nix build --impire ".#checks.aarch64-darwin.<test>" --no-link

# 4. Commit + push + PR
jj describe -m "<type>: <what and why>"
jj bookmark set <branch> -r @
jj git push --bookmark <branch>
gh pr create ...

# 5. Watch CI
# 6. Stop here - human merges the PR

# 7. Mark done + unblock next
yx done "<yak name>"
yx tag rm "<next yak>" "@blocked"  # if applicable
yx sync
```

## Multi-Agent Coordination

Yaks syncs via git refs, so all agents in the same repo share the same task state.

### Claiming prevents conflicts
- `yx sync` before claiming pulls others' claims
- `yx start` sets wip state
- `yx sync` after claiming pushes your claim
- Other agents see wip and skip that yak

### @needs-human convention
```bash
yx tag add "yak name" "@needs-human"
cat <<'EOF' | yx context "yak name"
[existing context]

## Open Question
What should X do when Y happens?
EOF
yx sync
```

## Common Mistakes

| Mistake | Fix |
|---------|------|
| Skipping `yx sync` before/after claiming | Sync is mandatory -- other agents can't see your claim without it |
| Not checking state before `yx start` | Always `yx show` first to verify it's not already wip |
| Forgetting `yx ls` after adding yaks | Iron Law: `yx add` then `yx ls`, always |
| Using deep nesting for dependencies | Use flat structure + `## Prerequisites` + `@blocked` tags |
| Forgetting to unblock dependents | After completing a yak, remove `@blocked` from dependents |
| Not syncing after marking done | Others won't see completion without `yx sync` |
| Implementing a vague yak | Run `yak-needs-refinement.sh` first; flag if unclear |
| Two subagents editing the same file | Check context file paths before parallelizing |
| Forgetting `git add -A` before `nix build --impure` | Staged files must be visible for impure eval |
| Implementation before test | RED phase is mandatory; delete any code written before tests |
