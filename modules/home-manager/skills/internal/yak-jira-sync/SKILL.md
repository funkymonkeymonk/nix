---
name: yak-jira-sync
description: Use when creating Jira tickets from a yak backlog, syncing yaks to Jira, auditing whether open yaks have corresponding tickets, or ensuring a yak backlog and Jira board reflect the same work.
---

# Yak-Jira Sync

## Overview

Yaks are the source of truth for *what to do*. Jira is the source of truth for *visibility, prioritization, and stakeholder communication*. This skill keeps them aligned.

**Core rules:**
- Every open Jira ticket → one top-level yak, name leading with the ticket key
- Every implementation sub-task *with its own Jira ticket* → top-level yak
- Sub-tasks *without* their own Jira ticket → nested child yak under the parent ticket's yak
- Done yaks with no ticket → no action needed

## Structure

```
○ DEVEX-123: top-level story summary         ← ticket key leads the name
  ╰─ ○ sub-task without own ticket           ← no key, nested under parent
○ DEVEX-124: sub-task with its own ticket    ← top-level, key leads name
○ DEVEX-125: another independent story       ← top-level, key leads name
```

**The name rule:** If a yak has a Jira ticket, the name MUST start with `TICKET-NNN:`.
This makes `yx ls` output scannable and lets anyone jump straight to the ticket.

## Sync Workflow

### Audit (existing backlog)

```bash
yx sync
yx ls --format json   # full tree to compare against Jira
```

1. Search Jira for open tickets in the relevant project/epic
2. Build a mapping table: yak name ↔ Jira key
3. For each open Jira ticket with no yak → create yak (see below)
4. For each open yak with a ticket but no key in name → rename it
5. For each open yak with a ticket that's nested under the wrong parent → move it to root
6. For each done Jira ticket whose yak is still open → mark yak done

### Creating a yak from a Jira ticket

```bash
# Name always leads with ticket key
yx add "DEVEX-123: <ticket summary>"
yx ls   # iron law: always ls after add

# Set context — include Jira key, acceptance criteria, and docs URLs
cat <<'EOF' | yx context "DEVEX-123: <ticket summary>"
# Goal
<what and why, from ticket description>

## Jira
DEVEX-123

## Acceptance Criteria
- [ ] <from ticket>
EOF

yx sync
```

### Renaming an existing yak to lead with ticket key

```bash
yx rename "old yak name" "DEVEX-123: old yak name"
yx sync
```

### Moving a yak to the correct level

```bash
# Has its own ticket → must be top-level
yx move "yak-name" --to-root
yx ls

# Is a pure sub-task (no own ticket) → nest under parent
yx move "sub-task name" --under "DEVEX-123: parent name"
yx ls
```

## Context Convention

Every yak with a Jira ticket must include a `## Jira` section in its context:

```markdown
## Jira
DEVEX-123
```

This lets agents and humans find the ticket without parsing the yak name.
For yaks with decisions to make (review/planning tickets), also include:

```markdown
## Docs
https://docs.example.com/relevant-page

## Decisions to make
- [ ] Decision A
- [ ] Decision B
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| Open ticket, no yak | `yx add "DEVEX-NNN: summary"` + set context |
| Open yak has ticket but name doesn't lead with key | `yx rename` |
| Yak has own ticket but nested under another yak | `yx move --to-root` |
| Sub-task has no own ticket, at root | `yx move --under "DEVEX-NNN: parent"` |
| Jira ticket is Done, yak still open | `yx done "DEVEX-NNN: ..."` |
| Jira ticket is Done, yak has open children | `yx done --recursive "DEVEX-NNN: ..."` or close individually |
| Yak done, no ticket | No action needed |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Nesting a yak that has its own Jira ticket | If it has its own ticket, it belongs at root |
| Leading with the summary instead of the key | Key first: `DEVEX-123: summary`, not `summary (DEVEX-123)` |
| Forgetting `yx ls` after every `yx add` or `yx move` | Iron law — always verify structure after mutation |
| Forgetting `yx sync` after a batch of changes | Always sync when done with a session of changes |
| Not adding `## Jira` to context | Future agents can't find the ticket without it |
| Creating a Jira ticket without a corresponding yak | Create the yak immediately; don't let them drift apart |
