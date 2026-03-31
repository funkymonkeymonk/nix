# Story Review Checklist

Use this checklist before running Ralph to ensure your PRD is ready for autonomous execution.

## PRD-Level Checks

### Metadata
- [ ] `project` name is set
- [ ] `branchName` starts with `ralph/`
- [ ] `description` is a clear one-liner

### Story Count
- [ ] PRD has 3-10 user stories (optimal range)
- [ ] If >10 stories, consider splitting into multiple PRDs

## Per-Story Checks

Run through each story:

### US-XXX: ________________________________

#### Size Check
- [ ] Story can complete in one context window (~30 min agent work)
- [ ] Story touches 1-3 files maximum
- [ ] Story has single clear outcome

#### Title Check
- [ ] Title under 60 characters
- [ ] Title starts with action verb (Add, Create, Update, Remove, Fix)
- [ ] Title is specific, not vague

#### Description Check
- [ ] Follows "As a [role], I want [goal] so that [benefit]" format
- [ ] Role is specific (developer, user, admin, operator)
- [ ] Goal is concrete and bounded
- [ ] Benefit explains the "why"

#### Acceptance Criteria Check
- [ ] Has 2-5 criteria (not too few, not too many)
- [ ] Each criterion is binary (pass/fail)
- [ ] No subjective language ("clean", "good", "proper")
- [ ] Specific paths/names where applicable
- [ ] Includes verification step:
  - [ ] "Typecheck passes" OR
  - [ ] "Tests pass" OR
  - [ ] "nix flake check passes" OR
  - [ ] "Verify in browser using dev-browser skill"

#### Dependencies Check
- [ ] Priority number reflects dependencies
- [ ] No story depends on a higher-priority story
- [ ] Foundation work (schema, types) comes first

#### Initial State Check
- [ ] `passes` is set to `false`
- [ ] `notes` is empty string `""`

## Common Issues to Fix

### Story Too Large
Signs:
- More than 5 acceptance criteria
- Touches more than 3 files
- Contains words like "and", "also", "additionally"

Fix: Split into multiple stories

### Vague Criteria
Signs:
- Uses subjective words
- No specific paths or values
- Can't be automated

Fix: Add specifics (file paths, exact values, commands)

### Missing Dependencies
Signs:
- UI story before API story
- API story before schema story
- Integration before unit components

Fix: Reorder priorities

### No Verification
Signs:
- No typecheck/test criterion
- No way to confirm completion

Fix: Add "Typecheck passes" or equivalent

## Final Verification

Before starting Ralph:

```bash
# Validate JSON syntax
cat prd.json | jq .

# Check story count
cat prd.json | jq '.userStories | length'

# List all stories with status
cat prd.json | jq '.userStories[] | {id, title, priority, passes}'

# Check for stories without verification criteria
cat prd.json | jq '.userStories[] | select(.acceptanceCriteria | map(test("passes|Verify")) | any | not) | .id'
```

## Ready to Run?

All boxes checked? Start Ralph:

```bash
./ralph.sh
```

Monitor progress:
```bash
# Watch story completion
watch -n 5 'cat prd.json | jq ".userStories[] | {id, passes}"'

# Check learnings
tail -f progress.txt
```
