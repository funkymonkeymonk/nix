---
name: ralph-specs
description: Write specifications optimized for Ralph Loop autonomous agent execution
---

# Ralph-Compatible Spec Writing

## Overview

Write Product Requirement Documents (PRDs) optimized for Ralph Loop execution. Ralph runs AI coding agents in autonomous loops until all user stories pass - specs must be unambiguous, atomic, and machine-verifiable.

## When to Use

- Planning features for autonomous AI implementation
- Converting ideas into Ralph-executable PRDs
- Breaking down large tasks into atomic user stories
- Preparing work for unattended agent execution

## Key Principles

### 1. Fresh Context Each Iteration
Each Ralph loop iteration spawns a NEW agent with clean context. The agent only knows:
- The current `prd.json` (which stories pass/fail)
- Git history from previous iterations  
- `progress.txt` learnings
- `AGENTS.md` patterns and conventions

**Implication**: Every story must be self-contained with all needed context.

### 2. One Context Window Per Story
Stories must complete in a single agent context window (~32K-128K tokens depending on model).

**Right-sized stories:**
- Add a database column and migration
- Create a single UI component
- Add one API endpoint
- Update a config file with new options

**Too large (split these):**
- "Build the entire dashboard"
- "Add authentication"  
- "Refactor the API layer"
- "Migrate from X to Y"

### 3. Machine-Verifiable Acceptance Criteria
Every criterion must be testable without human judgment:

**Good criteria:**
- "Typecheck passes"
- "All tests pass"
- "File `src/config.ts` exports `DatabaseConfig` type"
- "Running `curl localhost:3000/api/health` returns 200"

**Bad criteria:**
- "Code is clean"
- "UI looks good"
- "Performance is acceptable"

### 4. Explicit Dependencies via Priority
Stories execute in priority order. Lower numbers run first.

```json
{ "priority": 1, "title": "Add database schema" }
{ "priority": 2, "title": "Add API endpoint (depends on schema)" }
{ "priority": 3, "title": "Add UI component (depends on API)" }
```

## PRD Structure

### Required Format: `prd.json`

```json
{
  "project": "ProjectName",
  "branchName": "ralph/feature-name",
  "description": "One-line feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short descriptive title (max 60 chars)",
      "description": "As a [role], I want [goal] so that [benefit]",
      "acceptanceCriteria": [
        "Specific, testable criterion",
        "Another testable criterion",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Field Requirements

| Field | Required | Description |
|-------|----------|-------------|
| `project` | Yes | Project identifier |
| `branchName` | Yes | Git branch for this work (prefix with `ralph/`) |
| `description` | Yes | One-line feature summary |
| `userStories` | Yes | Array of user stories |
| `id` | Yes | Unique identifier (US-001, US-002, etc.) |
| `title` | Yes | Short title (max 60 characters) |
| `description` | Yes | User story format: As a [role], I want [goal]... |
| `acceptanceCriteria` | Yes | Array of testable criteria |
| `priority` | Yes | Execution order (1 = first) |
| `passes` | Yes | Start as `false`, agent sets `true` when done |
| `notes` | No | Agent adds learnings here |

## Writing Process

### Step 1: Define the Feature
Start with a clear, bounded feature description:
- What problem does this solve?
- Who benefits?
- What's the minimal viable scope?

### Step 2: Decompose into Stories
Break into 3-10 atomic stories. Each story should:
- Take 5-30 minutes for an agent to implement
- Have clear start and end states
- Be independently verifiable

### Step 3: Order by Dependencies
Assign priorities based on dependencies:
1. Data/schema changes first
2. Backend logic second
3. API endpoints third
4. UI components last

### Step 4: Write Acceptance Criteria
For each story, write 2-5 criteria that are:
- Binary (pass/fail, no partial credit)
- Automatable (typecheck, tests, file existence)
- Specific (exact file paths, function names)

### Step 5: Add Verification Commands
Always include at least one of:
- `Typecheck passes`
- `All tests pass`
- `Verify in browser using dev-browser skill` (for UI)

## Acceptance Criteria Patterns

### For Data/Schema Changes
```json
"acceptanceCriteria": [
  "Migration file exists at db/migrations/NNNN_add_priority.sql",
  "Migration runs without errors",
  "Schema includes priority column with type VARCHAR(10)",
  "Typecheck passes"
]
```

### For API Endpoints
```json
"acceptanceCriteria": [
  "GET /api/tasks returns JSON array",
  "Response includes 'priority' field on each task",
  "Invalid requests return 400 with error message",
  "Typecheck passes",
  "API tests pass"
]
```

### For UI Components
```json
"acceptanceCriteria": [
  "PriorityBadge component exists at src/components/PriorityBadge.tsx",
  "Component accepts 'priority' prop of type 'high' | 'medium' | 'low'",
  "Renders colored badge (red=high, yellow=medium, gray=low)",
  "Typecheck passes",
  "Verify in browser using dev-browser skill"
]
```

### For Configuration Changes
```json
"acceptanceCriteria": [
  "Config file updated at path/to/config.nix",
  "New option 'services.myapp.priority' added",
  "Option has type 'enum [\"high\" \"medium\" \"low\"]'",
  "Default value is 'medium'",
  "nix flake check passes"
]
```

## Common Mistakes

### Stories Too Large
**Bad:** "Implement user authentication"
**Good:** Split into:
1. Add user table schema
2. Add password hashing utility
3. Add login API endpoint
4. Add session management
5. Add login UI form

### Vague Acceptance Criteria
**Bad:** "Feature works correctly"
**Good:** "POST /api/login with valid credentials returns 200 and session token"

### Missing Dependencies
**Bad:** UI story at priority 1, API at priority 3
**Good:** Schema (1) -> API (2) -> UI (3)

### No Verification Step
**Bad:** Only functional criteria
**Good:** Always include "Typecheck passes" or equivalent

## Templates

See bundled templates:
- `templates/prd.json` - Empty PRD template
- `templates/story-template.md` - Story writing guide

## Examples

See bundled examples:
- `examples/feature-prd.json` - New feature implementation
- `examples/refactor-prd.json` - Code refactoring
- `examples/nix-config-prd.json` - Nix configuration change

## Checklist Before Running Ralph

Use `checklists/story-review.md` to verify:
- [ ] Each story fits in one context window
- [ ] All acceptance criteria are testable
- [ ] Dependencies reflected in priorities
- [ ] Verification commands included
- [ ] No ambiguous language

## Related Skills

- `prd-review` - Display PRD in human-readable format
- `verification-before-completion` - Run verification commands
