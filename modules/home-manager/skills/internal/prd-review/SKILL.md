---
name: prd-review
description: Display PRD files in human-readable format for review and status tracking
---

# PRD Review

## Overview

Convert `prd.json` files into human-readable format for review, status tracking, and progress monitoring. Helps humans understand and validate PRDs before and during Ralph execution.

## When to Use

- Reviewing a PRD before starting Ralph
- Checking progress during Ralph execution
- Sharing PRD status with team members
- Validating story structure and dependencies

## Commands

### Full PRD Review

Display complete PRD with all details:

```
Review the PRD at prd.json in human-readable format
```

### Status Summary

Quick overview of completion status:

```
Show PRD status summary for prd.json
```

### Single Story Detail

Deep dive into one story:

```
Show details for story US-003 from prd.json
```

## Output Formats

### Full Review Format

When asked to review a PRD, output in this format:

```markdown
# PRD: [project]

**Branch:** `[branchName]`
**Description:** [description]

## Progress

[■■■■■□□□□□] 5/10 stories complete (50%)

## Stories

### ✅ US-001: [title] (Priority 1)
**Status:** COMPLETE

> [description]

**Acceptance Criteria:**
- ✅ [criterion 1]
- ✅ [criterion 2]

**Notes:** [any notes from agent]

---

### 🔄 US-002: [title] (Priority 2)  
**Status:** IN PROGRESS (current)

> [description]

**Acceptance Criteria:**
- ✅ [completed criterion]
- ⬜ [pending criterion]

---

### ⬜ US-003: [title] (Priority 3)
**Status:** PENDING

> [description]

**Acceptance Criteria:**
- ⬜ [criterion 1]
- ⬜ [criterion 2]
```

### Status Summary Format

```markdown
# [project] - Status Summary

**Branch:** `[branchName]`
**Progress:** [■■■■■□□□□□] 5/10 (50%)

| ID | Title | Priority | Status |
|----|-------|----------|--------|
| US-001 | [title] | 1 | ✅ Complete |
| US-002 | [title] | 2 | 🔄 In Progress |
| US-003 | [title] | 3 | ⬜ Pending |

**Next Up:** US-003 - [title]
**Estimated Remaining:** 5 stories
```

### Story Detail Format

```markdown
# US-003: [title]

**Priority:** 3 of 10
**Status:** ⬜ Pending
**Dependencies:** US-001, US-002

## Description

> As a [role], I want [goal] so that [benefit].

## Acceptance Criteria

| # | Criterion | Status |
|---|-----------|--------|
| 1 | [criterion text] | ⬜ |
| 2 | [criterion text] | ⬜ |
| 3 | Typecheck passes | ⬜ |

## Size Analysis

- **Files affected:** ~2-3 (estimated)
- **Complexity:** Medium
- **Est. iterations:** 1-2

## Notes

[Any notes from previous iterations]
```

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

When reviewing, check for issues:

### Dependency Violations
Flag if a story depends on incomplete higher-priority stories:

```markdown
⚠️ **Dependency Warning**
US-005 (Priority 5) may depend on:
- US-003 (Priority 3) - ⬜ Not complete
- US-004 (Priority 4) - ⬜ Not complete

Consider completing dependencies first.
```

### Orphan Detection
Flag stories that nothing depends on (potential scope creep):

```markdown
ℹ️ **Note:** US-008 appears to be standalone (no other stories depend on it).
This is fine if intentional, but verify it's in scope.
```

## Quality Checks

When reviewing, flag potential issues:

### Size Warnings
```markdown
⚠️ **Size Warning:** US-004 has 7 acceptance criteria.
Consider splitting into smaller stories.
```

### Vague Criteria
```markdown
⚠️ **Vague Criterion:** "Code is well-organized" in US-003
This is not machine-verifiable. Suggest specific check.
```

### Missing Verification
```markdown
⚠️ **Missing Verification:** US-005 has no typecheck/test criterion.
Add "Typecheck passes" or equivalent.
```

## Example Usage

### Input PRD
```json
{
  "project": "TaskApp",
  "branchName": "ralph/priorities",
  "description": "Add priority system",
  "userStories": [
    {"id": "US-001", "title": "Add priority column", "passes": true, ...},
    {"id": "US-002", "title": "Add API endpoint", "passes": false, ...},
    {"id": "US-003", "title": "Add UI component", "passes": false, ...}
  ]
}
```

### Output Review
```markdown
# PRD: TaskApp

**Branch:** `ralph/priorities`
**Description:** Add priority system

## Progress

[■■■□□□□□□□] 1/3 stories complete (33%)

## Stories

### ✅ US-001: Add priority column (Priority 1)
**Status:** COMPLETE
...

### 🔄 US-002: Add API endpoint (Priority 2)
**Status:** IN PROGRESS
...

### ⬜ US-003: Add UI component (Priority 3)
**Status:** PENDING
...
```

## Integration with Ralph

### Pre-Run Review
```
Review prd.json and flag any issues before I run Ralph
```

### Progress Check (During Run)
```
Show current Ralph progress for prd.json
```

### Post-Run Summary
```
Summarize what Ralph completed in prd.json
```

## Related Skills

- `ralph-specs` - Write Ralph-compatible specifications
- `verification-before-completion` - Run verification commands
