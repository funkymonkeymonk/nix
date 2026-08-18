# PRD Review — Output Format Templates

## Contents
- Full Review Format
- Status Summary Format
- Story Detail Format
- Worked Example

## Full Review Format

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

## Status Summary Format

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

## Story Detail Format

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

## Worked Example

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
