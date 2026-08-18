---
name: prd-review
description: Use when reviewing a PRD before or during Ralph Loop execution, checking story completion status, or validating story structure and dependencies in a prd.json file.
---

# PRD Review

## Overview

Convert `prd.json` files into human-readable format for review, status tracking, and progress monitoring. Helps humans understand and validate PRDs before and during Ralph execution.

**Full output format templates** (full review, status summary, story detail, worked example): [references/output-formats.md](references/output-formats.md)

## Commands

- **Full review**: "Review the PRD at prd.json in human-readable format"
- **Status summary**: "Show PRD status summary for prd.json"
- **Single story detail**: "Show details for story US-003 from prd.json"

See [references/output-formats.md](references/output-formats.md) for the exact markdown template for each.

## Status Indicators

Use these consistently:

| Symbol | Meaning |
|--------|---------|
| ✅ | Complete (`passes: true`) |
| 🔄 | In Progress (first `passes: false` by priority) |
| ⬜ | Pending (not yet started) |
| ❌ | Blocked (has failing dependency) |

## Progress Bar

Generate progress bar based on completion:

```
0%:   [□□□□□□□□□□]
10%:  [■□□□□□□□□□]
50%:  [■■■■■□□□□□]
100%: [■■■■■■■■■■]
```

## Dependency Analysis

Flag if a story depends on incomplete higher-priority stories:

```markdown
⚠️ **Dependency Warning**
US-005 (Priority 5) may depend on:
- US-003 (Priority 3) - ⬜ Not complete
- US-004 (Priority 4) - ⬜ Not complete

Consider completing dependencies first.
```

Flag stories that nothing depends on (potential scope creep):

```markdown
ℹ️ **Note:** US-008 appears to be standalone (no other stories depend on it).
This is fine if intentional, but verify it's in scope.
```

## Quality Checks

Flag potential issues while reviewing:

| Issue | Example |
|-------|---------|
| **Size** | "⚠️ US-004 has 7 acceptance criteria. Consider splitting into smaller stories." |
| **Vague criteria** | "⚠️ 'Code is well-organized' in US-003 is not machine-verifiable. Suggest specific check." |
| **Missing verification** | "⚠️ US-005 has no typecheck/test criterion. Add 'Typecheck passes' or equivalent." |

## Related Skills

- `ralph-specs` — Write Ralph-compatible specifications
