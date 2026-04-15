---
name: shave-yaks
description: Use when you want to autonomously work through a yak backlog end-to-end — triaging, implementing, testing, and shipping PRs until all yaks are done or flagged for refinement
---

# Shave Yaks

## Overview

Autonomous yak shaving: triage the backlog, implement each yak in an isolated jj workspace with TDD/BDD tests, ship a PR, watch CI, merge, and loop until done. Yaks with insufficient context get flagged for human refinement instead of guessed at.

**Key mental model:** One yak = one jj workspace = one subagent = one PR. Parallel where file conflicts are impossible.

**Required skills:** `yak-shaving` (yx commands), `jj` (workspace/PR workflow), `watch-ci-jobs` (CI polling)

## When to Use

- `/shave` — work through the entire backlog autonomously
- Batch of yaks exist and you want to ship them without manual orchestration
- After a planning session that produced many new todo yaks

## Scripts

All scripts live in `scripts/` relative to this skill:

| Script | Purpose |
|--------|---------|
| `yak-triage.sh` | Find actionable (todo, leaf, unblocked) yaks |
| `yak-claim.sh "name"` | Safely claim a yak (sync → check → start → sync) |
| `yak-needs-refinement.sh "name"` | Test if yak has enough context to implement |
| `yak-worker-prompt.sh "name"` | Generate full subagent implementation prompt |
| `yak-mark-refinement.sh "name" "reason"` | Tag yak @needs-human with reason |

## The /shave Loop

```
WHILE actionable yaks exist:
  1. yx sync                          — pull latest state
  2. yak-triage.sh                    — find todo leaf yaks
  3. FOR EACH batch of compatible yaks (no file conflicts):
     a. yak-needs-refinement.sh       — test clarity
        → unclear: yak-mark-refinement.sh, skip
        → clear:   yak-claim.sh, dispatch subagent
  4. WAIT for all subagents to complete
  5. yx sync                          — pull done state
  6. Check if any remain
```

**Compatibility check:** Two yaks are safe to run in parallel if they don't touch the same files. Check yak contexts for overlapping file paths. When in doubt, serialize.

## BDD/TDD Requirements for Each Yak

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

Use `yak-needs-refinement.sh` to automate this check. Don't guess at vague yaks — flag them and move on. A wrong implementation wastes more time than a refinement request.

## Parallelism Rules

**Safe to parallelize:** Yaks touching different files/modules (checked via context file paths)

**Must serialize:**
- Two yaks editing the same Nix file
- A yak + its parent (parent blocked by child)
- Yaks that both modify `flake.nix` or `tests/default.nix` (high conflict surface)

**Practical limit:** 2-3 parallel subagents. More causes merge conflicts.

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
git add -A && nix build --impure ".#checks.aarch64-darwin.<test>" --no-link

# 4. Commit + push + PR
jj describe -m "<type>: <what and why>"
jj bookmark set <branch> -r @
jj git push --bookmark <branch>
gh pr create ...

# 5. Watch CI (poll gh pr view --json statusCheckRollup)
# 6. Merge when green
gh pr merge <n> --repo <repo> --squash --delete-branch --admin

# 7. Mark done
yx done "<yak name>" && yx sync
jj workspace forget <name> && rm -rf .workspaces/<name>
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Implementing a vague yak | Run `yak-needs-refinement.sh` first; flag if unclear |
| Two subagents editing the same file | Check context file paths before parallelizing |
| Forgetting `git add -A` before `nix build --impure` | Staged files must be visible for impure eval |
| Claiming without syncing | Always `yx sync` before AND after `yx start` |
| Merging with failing CI | Wait for all checks — `"conclusion":"SUCCESS"` |
| Implementation before test | RED phase is mandatory; delete any code written before tests |

## Finishing Up

After all yaks are done or flagged:

```bash
yx sync
yx ls  # Show final state: done ✓, @needs-human ○ flagged
```

Report to human:
- How many yaks shaved
- Which yaks were flagged for refinement and why
- Any PRs that needed human intervention
