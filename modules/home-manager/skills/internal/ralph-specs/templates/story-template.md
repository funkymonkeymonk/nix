# User Story Template for Ralph Loops

## Story Structure

```
ID: US-XXX
Title: [Action verb] [thing] [context] (max 60 chars)
```

## Description Format

Use the standard user story format:

```
As a [role],
I want [goal/desire],
so that [benefit/value].
```

### Role Examples
- `developer` - Someone writing code
- `user` - End user of the application  
- `admin` - Administrator with elevated privileges
- `system` - Automated process or service
- `operator` - Person managing infrastructure

### Goal Examples
- "to add a priority field to tasks"
- "to filter tasks by status"
- "to receive notifications when builds fail"
- "to configure the service via environment variables"

### Benefit Examples
- "I can track what's most important"
- "I can focus on relevant items"
- "I can respond to issues quickly"
- "deployment is more flexible"

## Acceptance Criteria Guidelines

### Structure
Write 2-5 criteria per story. Each criterion should be:
- **Binary**: Pass or fail, no partial credit
- **Specific**: Exact paths, names, values
- **Testable**: Can be verified by automation

### Formula
```
[Subject] [verb] [expected state/behavior]
```

### Good Examples

**File existence:**
```
File exists at src/components/PriorityBadge.tsx
```

**Type/interface:**
```
TaskPriority type exported from src/types/task.ts
```

**Behavior:**
```
POST /api/tasks with priority field saves to database
```

**Validation:**
```
Invalid priority value returns 400 error with message
```

**Build/check:**
```
Typecheck passes
All tests pass
nix flake check passes
```

**UI verification:**
```
Verify in browser using dev-browser skill
```

### Bad Examples (Avoid These)

```
Code is well-organized          # Subjective
Performance is acceptable       # Unmeasurable  
Feature works as expected       # Vague
UI looks correct                # Subjective
```

## Size Guidelines

### Right-Sized Story (5-30 min agent work)
- Single file creation/modification
- One database migration
- One API endpoint
- One UI component
- One configuration change

### Too Large (Split These)
- Multiple unrelated files
- Feature spanning data + API + UI
- Refactoring multiple modules
- Any story with >5 acceptance criteria

## Priority Assignment

### Rule: Dependencies determine priority

```
Priority 1: Foundation (schema, types, config)
Priority 2: Core logic (services, utilities)
Priority 3: Integration (API, handlers)
Priority 4: Presentation (UI, formatting)
Priority 5: Polish (docs, cleanup)
```

### Example Dependency Chain

```
US-001 (P1): Add priority column to tasks table
    |
US-002 (P2): Add TaskPriority type to shared types
    |
US-003 (P3): Update createTask API to accept priority
    |
US-004 (P4): Add priority selector to task form UI
    |
US-005 (P5): Add priority to task list documentation
```

## Complete Example

```json
{
  "id": "US-003",
  "title": "Add priority parameter to createTask API",
  "description": "As a developer, I want the createTask API to accept a priority parameter so that tasks can be created with different priority levels.",
  "acceptanceCriteria": [
    "POST /api/tasks accepts optional 'priority' field in request body",
    "Priority must be one of: 'high', 'medium', 'low'",
    "Default priority is 'medium' when not specified",
    "Invalid priority value returns 400 with error message",
    "Typecheck passes",
    "API tests pass"
  ],
  "priority": 3,
  "passes": false,
  "notes": ""
}
```

## Checklist Before Adding Story

- [ ] Title under 60 characters
- [ ] Description follows As/I want/So that format
- [ ] 2-5 acceptance criteria
- [ ] All criteria are binary (pass/fail)
- [ ] No subjective language
- [ ] Includes verification step (typecheck/tests)
- [ ] Priority reflects dependencies
- [ ] Story fits in one context window
