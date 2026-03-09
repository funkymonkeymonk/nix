---
name: refining-specs
description: Use when a specification has open questions requiring research, technical decisions, or user input to resolve
---

# Refining Specifications

## Overview

Systematically resolve open questions in specifications through research subagents, each producing a single commit. Questions requiring user input are flagged and queued while unblocked work continues.

## When to Use

- Spec has "Open Questions" section with unresolved items
- Technical decisions need research before committing to an approach
- Architecture choices require exploring alternatives
- User has asked to "resolve questions" or "refine the spec"

## Core Principles

### 1. One Question, One Subagent, One Commit
Each open question gets its own subagent session that:
- Researches the question thoroughly
- Makes a decision with documented rationale
- Updates the spec with findings
- Commits all changes as a single atomic unit

### 2. Blocked vs Unblocked
Questions are either:
- **Unblocked**: Can be resolved through research alone
- **Blocked**: Requires user input (preference, access, budget, etc.)

When a subagent discovers it needs user input:
1. Document research findings so far
2. Add a NEW question describing what input is needed
3. Commit progress
4. Return to lead agent

### 3. Sequential Processing with Parallel Progress
Process questions one at a time to maintain clean git history, but:
- Push after each completed question
- Report blocked questions immediately
- Continue to next unblocked question

## Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                     LEAD AGENT                                   │
│                                                                  │
│  1. Read spec, identify open questions                          │
│  2. Create todo list for all questions                          │
│  3. For each unblocked question:                                │
│     ├─► Dispatch subagent with question context                 │
│     ├─► Subagent researches, decides, updates spec, commits     │
│     ├─► Push changes to origin                                  │
│     └─► Print decision summary                                  │
│  4. After all questions: report blocked questions + inputs      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Subagent Prompt Template

```markdown
You are researching Open Question N from the specification at `{spec_path}`.

**Question**: {question_text}

**Context**: {relevant_context}

**Your task**:
1. Research by:
   - Fetching relevant documentation
   - Understanding technical constraints
   - Exploring alternatives
   - Evaluating tradeoffs

2. Make a decision with rationale considering:
   - Technical feasibility
   - Security implications
   - User experience
   - Implementation complexity

3. Update the spec file to:
   - Remove this question from "Open Questions" section
   - Add decision to "Decisions" section with:
     - Research findings
     - Decision made
     - Rationale
   - Update implementation sections as needed

4. Create a commit:
   - Run `jj new` first (if using jj)
   - Make changes
   - Use `jj describe -m "docs: resolve {question_summary}"`

**If you need user input**: 
- Document your research findings
- Add a NEW question at bottom of "Open Questions" describing what input is needed
- Commit your progress
- Return summary of what's blocked and why

**Important**: Use jj for version control (not git).

Return:
1. What you researched and found
2. Decision made (or new question added if blocked)  
3. Commit created
```

## Decision Documentation Format

Each resolved question becomes a decision entry:

```markdown
### D{N}: {Decision Title} (resolved from Q{M})

**Decision**: {One sentence summary}

**Research Findings**:
1. {Key finding with source}
2. {Another finding}
3. {Comparison table if applicable}

**Implementation**:
{Code examples, configuration, or architecture changes}

**Rationale**:
- {Why this approach over alternatives}
- {Security/performance/UX considerations}
```

## Handling Blocked Questions

When subagent encounters need for user input:

```markdown
### Q{N}: {New Question Title}

**Background**: {Research done so far}

**Options identified**:
| Option | Pros | Cons |
|--------|------|------|
| A | ... | ... |
| B | ... | ... |

**Input needed**: {Specific question for user}
- Example: "Which approach do you prefer: A or B?"
- Example: "What is the budget for this service?"
- Example: "Do you have access to X?"
```

## Lead Agent Reporting

After each subagent completes:

```markdown
**Q{N} Complete** - Decision: {one-line summary}
```

After all questions processed:

```markdown
## Blocked Questions Requiring Input

| Question | Input Needed |
|----------|--------------|
| Q5 | Preference: polling vs webhooks? |
| Q7 | Budget for external service? |

## Decisions Made

| # | Question | Decision |
|---|----------|----------|
| D1 | {topic} | {decision} |
| D2 | {topic} | {decision} |
```

## Common Patterns

### Architecture Decisions
- Research official documentation first
- Check for existing patterns in codebase
- Consider platform limitations (NixOS, macOS, etc.)
- Evaluate build vs buy tradeoffs

### Security Decisions
- Research threat model implications
- Check industry standards (OWASP, NIST)
- Consider defense in depth
- Document attack vectors mitigated

### Integration Decisions
- Check API documentation
- Verify plugin/extension capabilities
- Test compatibility claims
- Document version requirements

## Anti-Patterns

### Answering Without Research
**Bad**: Making decisions based on assumptions
**Good**: Fetch documentation, test claims, verify capabilities

### Blocking on Preferences
**Bad**: Stopping when any subjective element exists
**Good**: Research objectively, present options, flag only truly subjective choices

### Mega-Commits
**Bad**: Researching all questions, then one giant commit
**Good**: One question = one subagent = one commit = one push

### Lost Context
**Bad**: Subagent returns "done" with no summary
**Good**: Return specific findings, decision, and commit reference

## Checklist

Before starting:
- [ ] Spec has "Open Questions" section
- [ ] Questions are enumerated/numbered
- [ ] Understand spec context and goals

For each question:
- [ ] Dispatch fresh subagent
- [ ] Subagent researches thoroughly
- [ ] Decision documented with rationale
- [ ] Spec updated (question removed, decision added)
- [ ] Single atomic commit created
- [ ] Changes pushed to origin
- [ ] Summary reported to user

After completion:
- [ ] All unblocked questions resolved
- [ ] Blocked questions listed with required inputs
- [ ] Decision summary provided
