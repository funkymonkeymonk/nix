# Add a Custom Skill

This guide shows you how to create a custom AI agent skill.

## Step 1: Create Skill Directory

```bash
mkdir -p modules/home-manager/skills/internal/my-skill
```

## Step 2: Create SKILL.md

Create `modules/home-manager/skills/internal/my-skill/SKILL.md`:

```markdown
---
name: my-skill
description: Brief description of what the skill does
---

# My Skill

## Overview

Describe what this skill helps with.

## When to Use

- Situation 1
- Situation 2

## Process

1. First step
2. Second step
3. Third step

## Key Principles

- Principle 1
- Principle 2
```

## Step 3: Register in Manifest

Add your skill to `modules/home-manager/skills/manifest.nix`:

```nix
skills = {
  # ... existing skills ...

  "my-skill" = {
    description = "Brief description";
    roles = ["developer"];  # Which roles get this skill
    source = {
      type = "internal";
      path = ./internal/my-skill;
    };
    deps = [];  # Dependencies on other skills
  };
};
```

## Step 4: Rebuild

Apply the configuration to install your skill:

```bash
# macOS
darwin-rebuild switch --flake .

# NixOS
sudo nixos-rebuild switch --flake .
```

## Step 5: Verify Installation

```bash
# Check skill is installed
ls ~/.config/opencode/skills/my-skill/

# Validate format
devenv tasks run agent-skills:validate
```

## Skill Dependencies

If your skill depends on others:

```nix
"my-skill" = {
  # ...
  deps = ["debugging" "tdd"];
};
```

Dependencies are installed automatically, even if the user's roles don't normally include them.

## Assigning to Multiple Roles

```nix
"my-skill" = {
  # ...
  roles = ["developer" "creative" "workstation"];
};
```

The skill installs for any user with at least one of these roles enabled.

> **See also:** [Skills Reference](../reference/skills.md) for the skill manifest format
