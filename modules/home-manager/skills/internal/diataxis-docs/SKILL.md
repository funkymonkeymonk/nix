---
name: diataxis-docs
description: Use when updating, rewriting, or auditing documentation to follow the Diataxis framework with its four distinct content types
---

# Diataxis Documentation

## Overview

Restructure documentation using the Diataxis framework - a systematic approach that organizes content into four distinct types based on user needs: **Tutorials**, **How-to guides**, **Reference**, and **Explanation**.

## When to Use

- Rewriting existing documentation
- Auditing docs for structure issues
- Creating new documentation from scratch
- Documentation feels disorganized or mixed
- Users can't find what they need

## The Four Quadrants

```
                    PRACTICAL                    THEORETICAL
            ┌─────────────────────┬─────────────────────┐
            │                     │                     │
  LEARNING  │     TUTORIALS       │    EXPLANATION      │
  (study)   │   learning-oriented │ understanding-oriented
            │                     │                     │
            ├─────────────────────┼─────────────────────┤
            │                     │                     │
   WORK     │   HOW-TO GUIDES     │    REFERENCE        │
  (apply)   │    goal-oriented    │  information-oriented
            │                     │                     │
            └─────────────────────┴─────────────────────┘
```

## Content Types

### Tutorials (Learning-oriented)
**Purpose:** Take the user through a learning experience
**User question:** "Can you teach me to...?"

| Do | Don't |
|----|-------|
| Let the user learn by doing | Explain concepts in depth |
| Get them started immediately | Offer choices or alternatives |
| Ensure every step works | Focus on edge cases |
| Show concrete results early | Assume prior knowledge |

**Language:** "In this tutorial, we will..." / "First, do x. Now, do y."

### How-to Guides (Goal-oriented)
**Purpose:** Help the user accomplish a specific task
**User question:** "How do I...?"

| Do | Don't |
|----|-------|
| Focus on the specific goal | Teach or explain |
| Provide numbered steps | Cover every option |
| Address real-world problems | Start from first principles |
| Be adaptable to variations | Include unrelated information |

**Language:** "This guide shows you how to..." / "If you want x, do y."

### Reference (Information-oriented)
**Purpose:** Describe the machinery and how to operate it
**User question:** "What is...?" / "What does X do?"

| Do | Don't |
|----|-------|
| Be accurate and complete | Explain why or how to use |
| Follow consistent structure | Include tutorials or guides |
| Mirror the code/system structure | Offer opinions |
| Provide examples of usage | Describe user journeys |

**Language:** "X is configured by..." / "The options are: a, b, c."

### Explanation (Understanding-oriented)
**Purpose:** Clarify and illuminate a topic
**User question:** "Why...?" / "Can you explain...?"

| Do | Don't |
|----|-------|
| Provide context and background | Provide step-by-step instructions |
| Discuss alternatives | Describe the machinery |
| Explain design decisions | Focus on a single correct way |
| Connect to broader concepts | Be exhaustive about details |

**Language:** "The reason for x is..." / "An alternative approach is..."

## Process

### 1. Audit Existing Content

For each document, ask:
1. What user need does this serve?
2. Does it mix multiple content types?
3. Where should a user find this?

Create an inventory:
```markdown
| Document | Current Type | Issues | Target Type |
|----------|--------------|--------|-------------|
| README.md | Mixed | Tutorial + Reference mixed | Split |
| setup.md | How-to | Contains explanation | Extract |
```

### 2. Classify and Split

**Mixed content signals:**
- "First, do X" followed by "This works because..."
- API reference with inline tutorials
- How-to guide that explains concepts
- Tutorial that lists all options

**Split rule:** Each document serves ONE quadrant.

### 3. Restructure Directory

```
docs/
├── tutorials/           # Learning experiences
│   ├── getting-started.md
│   └── first-project.md
├── how-to/              # Task completion
│   ├── configure-x.md
│   └── deploy-to-y.md
├── reference/           # Technical descriptions
│   ├── api.md
│   ├── config-options.md
│   └── cli-commands.md
└── explanation/         # Understanding
    ├── architecture.md
    └── design-decisions.md
```

### 4. Rewrite Each Document

**For each document:**
1. Identify target quadrant
2. Remove content belonging to other quadrants
3. Add cross-references to related content
4. Apply the appropriate tone and structure

**Cross-reference pattern:**
```markdown
> For a tutorial on getting started, see [Getting Started](../tutorials/getting-started.md).
> For details on all configuration options, see [Configuration Reference](../reference/config.md).
```

## Quick Reference

| Type | Orientation | Serves | Structure |
|------|-------------|--------|-----------|
| Tutorial | Learning | Study | Sequential lessons |
| How-to | Goal | Work | Numbered steps |
| Reference | Information | Work | Consistent descriptions |
| Explanation | Understanding | Study | Discursive prose |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| How-to that teaches | Extract learning content to tutorial |
| Tutorial with all options | Remove options, keep one path |
| Reference with "why" | Move explanations to explanation docs |
| Explanation with steps | Extract steps to how-to guide |
| README that does everything | Split into appropriate documents |

## Validation Checklist

- [ ] Each doc serves exactly one quadrant
- [ ] Tutorials have concrete outcomes
- [ ] How-to guides solve specific problems
- [ ] Reference is complete and consistent
- [ ] Explanation provides context, not instructions
- [ ] Cross-references connect related content
- [ ] Directory structure reflects the four types
