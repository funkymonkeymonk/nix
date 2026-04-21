---
name: yak-shaving
description: Use when tracking, planning, implementing, or reviewing work using yx (yaks), or when a human wants to triage @needs-human yaks interactively
---

# Yak Shaving

## Overview

Use `yx` (yaks) for shared task tracking across agents and humans. Yaks syncs via hidden git refs (`refs/notes/yaks`) using CRDTs -- multiple agents update simultaneously with zero conflicts.

**Key mental model:** `yx` owns **what** to do. Everything else owns **how** to do it.

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

## Four Workflows

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

### /review -- Human-in-the-loop backlog refinement

Use when: a human wants to work through `@needs-human` yaks interactively — deciding what's real, what's stale, and what's ready to implement.

**Step 1: Pick a topic cluster**

```bash
yx ls   # Show clusters; pick one with @needs-human children to focus on
```

**Step 2: For each yak — verify the code before deciding**

Never decide based on the title alone. Always inspect first:

```bash
yx show "yak name"                           # Read current state and context
grep -rn "<pattern>" modules/ targets/ os/   # Verify the problem exists in code
find . -name "<filename>" 2>/dev/null         # Confirm files mentioned actually exist
```

**Step 3: Apply one of four verdicts**

| Verdict | When | Commands |
|---------|------|----------|
| **Delete** | Stale — problem no longer exists in code | `yx rm "yak name"` |
| **Close** | Policy already decided, no code to write | `yx done "yak name"` |
| **Unblock** | Problem is real and scope is clear | Add context + `yx tag rm "yak name" "@needs-human"` |
| **Keep** | Genuinely needs human input | Update context with _why_ it's blocked, leave tag |

**Step 4: Write full context before unblocking**

A yak needs all three before `@needs-human` can be removed:

```bash
cat <<'EOF' | yx context "yak name"
# Problem
[What is wrong and exactly where in the code]

# Acceptance Criteria
- [ ] Specific, verifiable outcome
- [ ] Another verifiable outcome

# Files
- path/to/file.nix (what to change)
EOF

yx tag rm "yak name" "@needs-human"
```

No partial context — if you can write the problem but not the acceptance criteria, keep `@needs-human`.

**Step 5: Sync once at the end**

```bash
yx sync
```

**Batching tip:** Inspect all yaks in the cluster first, propose all verdicts to the human, then execute decisions in one pass before syncing.

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

Use when: a yak is claimed and ready to implement.

#### Step 1: Claim

```bash
yx sync
yx show "yak name"               # Verify state is todo, not wip
yx start "yak name"
yx sync
```

#### Step 2: Implement

Do the work. Use whatever version control workflow this repo requires.

#### Step 3: Store progress

```bash
echo "Implemented X, Y, Z. Tests pass." | yx field "yak name" progress
```

#### Step 4: Ship and mark done

Open a PR using the repo's normal workflow, then:

```bash
yx done "yak name"
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

When stuck or need a decision:
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
|---------|-----|
| Skipping `yx sync` before/after claiming | Sync is mandatory -- other agents can't see your claim without it |
| Not checking state before `yx start` | Always `yx show` first to verify it's not already wip |
| Forgetting `yx ls` after adding yaks | Iron Law: `yx add` then `yx ls`, always |
| Touching `.yaks/` directory directly | Use `yx` CLI only -- never `rm`, `mkdir`, `cat` on `.yaks/` |
| Not syncing yaks after marking done | Others won't see completion without `yx sync` |
| Deciding to delete/unblock based on yak title alone | Always grep the actual code first during /review |
| Unblocking without acceptance criteria | A yak without checkboxes will be re-flagged @needs-human by the next /shave |
