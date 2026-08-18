---
name: yak-shaving
description: Use when tracking, planning, implementing, or reviewing work using yx (yaks) with the autonomous /shave loop, or when multiple agents need to coordinate on shared tasks
---

# Yak Shaving

## Overview

Use `yx` (yaks) for shared task tracking across agents and humans. Yaks syncs via hidden git refs (`refs/notes/yaks`) using CRDTs -- multiple agents update simultaneously with zero conflicts.

**Key mental model:** `yx` owns **what** to do. Everything else owns **how** to do it.

**Full workflow walkthroughs** (/map, /review, /prepare, /work, /shave, PR cycle): [references/workflows.md](references/workflows.md)

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

## The Claim Protocol (MANDATORY — no exceptions)

**ALWAYS follow this sequence before starting work on a yak:**

```bash
yx sync                    # 1. Get latest state from other agents
yx show "yak name"         # 2. Check state -- if wip, pick another
yx start "yak name"        # 3. Claim it (sets state to wip)
yx sync                    # 4. Push your claim so others see it
```

**Never skip sync.** Without it, two agents can claim the same yak simultaneously. This is not a suggestion — skipping sync causes silent duplicate work, and there is no "just this once" exception.

## Dependency Model

Use `## Prerequisites` in context for dependencies (not deep nesting). Keep yaks flat under a story. Children block parents. Work leaves first, then their parents. The `@blocked` tag prevents triage from picking blocked yaks.

**Full dependency model detail (tagging, unblocking, examples)**: [references/workflows.md](references/workflows.md#dependency-model-detail)

## Scripts

All scripts live in `scripts/` relative to this skill:

| Script | Purpose |
|--------|---------|
| `yak-triage.sh` | Find actionable (todo, leaf, unblocked) yaks |
| `yak-claim.sh "name"` | Safely claim a yak (sync → check → start → sync) |
| `yak-needs-refinement.sh "name"` | Test if yak has enough context to implement |
| `yak-worker-prompt.sh "name"` | Generate full subagent implementation prompt |
| `yak-mark-refinement.sh "name" "reason"` | Tag yak @needs-human with reason |

## TDD/BDD Requirements (MANDATORY for every subagent — no exceptions)

```
RED:   Write failing test first
         → Nix: pkgs.runCommand that exits 1 without the fix
         → Shell: bash test with mock structures
         → CI: check verifying file structure
GREEN: Write minimal implementation to pass the test
REFACTOR: Clean up while keeping tests green
```

Acceptance criteria in yak context → test cases. Each `- [ ] criterion` becomes a test assertion.

**No exceptions:**
- Don't write implementation before the test exists
- Don't skip RED because "the fix is obvious"
- Don't manually verify instead of writing an automated test

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
