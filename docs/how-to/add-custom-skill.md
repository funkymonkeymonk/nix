# How to Add a Custom Skill

This guide shows you how to add a custom AI agent skill to this configuration.

## Steps

### 1. Create the Skill Directory

```bash
mkdir -p modules/home-manager/skills/internal/my-skill
```

### 2. Create SKILL.md

Create `modules/home-manager/skills/internal/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Brief description of what the skill does
---

# My Skill

## Overview

Describe what this skill helps the agent do.

## When to Use

- Situation 1
- Situation 2

## Process

1. Step one
2. Step two
3. Step three

## Key Principles

- Principle 1
- Principle 2
```

### 3. Register in Manifest

Add your skill to `modules/home-manager/skills/manifest.nix`:

```nix
{
  # ... existing skills ...

  "my-skill" = {
    description = "Brief description";
    roles = ["developer"];  # Which roles get this skill
    source = {
      type = "internal";
      path = ./internal/my-skill;
    };
    deps = [];  # Other skills this depends on
  };
}
```

### 4. Rebuild

```bash
devenv tasks run switch
```

The skill is now installed to `~/.config/opencode/skills/my-skill/`.

## Assigning Skills to Roles

Skills are installed based on role assignments:

| Roles | Skills Installed |
|-------|------------------|
| `developer` | debugging, tdd, writing-plans |
| `llm-client` | using-superpowers, jj |
| `creative` | brainstorming, writing-skills |

Modify the `roles` array in manifest.nix to control which roles receive the skill.

## Validating Skills

Check that skills follow the specification:

```bash
devenv tasks run agent-skills:validate
```

> For the complete list of available skills, see [Skills Reference](../reference/skills.md).
