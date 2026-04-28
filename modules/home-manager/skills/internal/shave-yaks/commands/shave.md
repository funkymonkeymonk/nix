---
description: Autonomously triage and implement yaks until all are shaved or flagged for refinement
agent: build
---

Work through the yak backlog autonomously using the `shave-yaks` skill.

## Your Mission

Loop through all actionable yaks until none remain. For each yak:
- If it has clear acceptance criteria and file context → implement it (TDD/BDD, PR, CI)
- If it's unclear → flag it with @needs-human and move on

**Do not stop until every leaf yak is either done ✓ or tagged @needs-human.**

## Setup

Locate the skill scripts:
```bash
SKILL_DIR="$HOME/.config/opencode/skills/shave-yaks/scripts"
```

## The Loop

```bash
yx sync
while true; do
  count=$("$SKILL_DIR/yak-triage.sh" --count 2>/dev/null || echo 0)
  [[ "$count" -eq 0 ]] && break

  # Get actionable yaks
  yaks=$("$SKILL_DIR/yak-triage.sh" --names)

  # For each yak, decide: implement or flag
  # Dispatch compatible yaks as parallel subagents
  # Wait for all to complete before next round
done
```

## Implementation Rules

Load the `shave-yaks` skill for the full workflow. Key requirements:

1. **Sync first** — `yx sync` before every triage pass
2. **Triage before acting** — use `yak-triage.sh` to find actionable yaks
3. **Check refinement need** — run `yak-needs-refinement.sh` before claiming any yak
4. **Claim with protocol** — use `yak-claim.sh` (sync → check → start → sync)
5. **Dispatch subagents** — use `yak-worker-prompt.sh` to generate each subagent's prompt
6. **Parallel where safe** — check contexts for file overlap; serialize when in doubt
7. **TDD mandatory** — every subagent must write tests BEFORE implementation
8. **BDD style** — acceptance criteria map to test assertions on desired outcomes
9. **Full PR cycle** — each subagent does: implement → validate → commit → PR → CI. Stop there — human merges.

## Parallelism

Check yak contexts for overlapping file paths. Run non-overlapping yaks in parallel subagents. Serialize yaks that touch the same files. Limit to 2-3 parallel subagents.

## When a Yak Needs Refinement

```bash
reason=$("$SKILL_DIR/yak-needs-refinement.sh" "yak name" 2>&1) || {
  "$SKILL_DIR/yak-mark-refinement.sh" "yak name" "$reason"
  # skip to next yak
}
```

## When Done

Report:
- Count of yaks shaved (PRs created)
- Count flagged for refinement (with reasons)
- Any open issues requiring human attention
