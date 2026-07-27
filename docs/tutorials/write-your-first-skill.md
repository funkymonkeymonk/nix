# Write Your First Skill

In this tutorial, you'll create an AI agent skill and deploy it through the Nix configuration. By the end, your skill will be installed for any agent harness (OpenCode, Claude Code, Pi) on machines with the right roles enabled.

## What You'll Learn

- How skills are structured (SKILL.md with frontmatter)
- How to register a skill in the manifest
- How role-gating works (skills install based on enabled roles)
- How to verify the skill is deployed

## Prerequisites

- Completed [Getting Started](getting-started.md)
- A machine with `developer` or `opencode` role enabled
- About 15 minutes

## Step 1: Create the Skill Directory

Skills live in `modules/home-manager/skills/internal/`. Create a directory for your skill:

```bash
mkdir -p modules/home-manager/skills/internal/code-review-checklist
```

## Step 2: Write the SKILL.md

Create `modules/home-manager/skills/internal/code-review-checklist/SKILL.md`:

```markdown
---
name: code-review-checklist
description: Use when reviewing code changes before approving a PR or merging a branch
---

# Code Review Checklist

## Overview

A systematic checklist for reviewing code changes. Ensures consistent, thorough reviews.

## When to Use

- Reviewing a pull request
- Checking your own code before submitting
- Pair-reviewing with another agent

## Checklist

### Correctness
- Does the code do what the description says?
- Are edge cases handled?
- Are error paths covered?

### Style
- Does it follow existing patterns in the codebase?
- Are names clear and consistent?
- Is there unnecessary complexity?

### Testing
- Are new behaviors tested?
- Do existing tests still pass?
- Are edge cases covered by tests?

### Documentation
- Are public interfaces documented?
- Are non-obvious decisions explained in comments?
- Is the commit message clear?
```

The frontmatter is important:
- `name` must use only letters, numbers, and hyphens
- `description` should start with "Use when..." and describe triggering conditions, not workflow

## Step 3: Register in the Manifest

Open `modules/home-manager/skills/manifest.nix` and add your skill:

```nix
"code-review-checklist" = {
  description = "Use when reviewing code changes before approving a PR or merging a branch";
  roles = ["developer" "opencode" "claude"];
  source = {
    type = "internal";
    path = ./internal/code-review-checklist;
  };
  deps = [];
};
```

The `roles` list controls which machines get this skill. Anyone with `developer`, `opencode`, or `claude` enabled will have it installed.

## Step 4: Validate

```bash
devenv tasks run check:lint
devenv tasks run test:darwin-eval
```

Both should pass. If the eval fails, check that:
- The `path` in the manifest points to the correct directory
- The `source.type` is `"internal"`

## Step 5: Build and Apply

```bash
# macOS
darwin-rebuild switch --flake .

# Or use the alias
s
```

## Step 6: Verify Installation

Check that the skill was deployed:

```bash
ls ~/.config/opencode/skills/code-review-checklist/
```

You should see `SKILL.md` (as a symlink into the Nix store).

Read it back to confirm:

```bash
cat ~/.config/opencode/skills/code-review-checklist/SKILL.md
```

## Step 7: Test It

Open OpenCode (or your preferred agent harness) and ask:

```
Review the latest changes on this branch using the code review checklist
```

The agent should find and load your skill, then follow the checklist structure.

## Going Further: Skill Dependencies

If your skill depends on another skill being present:

```nix
"code-review-checklist" = {
  # ...
  deps = ["debugging"];  # debugging skill installs too, even if role doesn't include it
};
```

## Going Further: Adding Slash Commands

Skills can bundle slash commands (OpenCode only). Add a `commands` section:

```nix
"code-review-checklist" = {
  # ...
  commands = {
    path = ./internal/code-review-checklist/commands;
    list = ["review"];
  };
};
```

Then create `commands/review.md` with the command definition.

## What You've Learned

- Skills are SKILL.md files with YAML frontmatter
- The manifest in `manifest.nix` controls which roles get which skills
- Skills deploy as Nix store symlinks via home-manager
- Dependencies ensure prerequisite skills are always present
- Always validate with lint + eval before applying

## What's Next

- **See all existing skills**: [Skills Reference](../reference/skills.md)
- **Understand why skills are Nix-managed**: [Agent Skills System](../explanation/agent-skills.md)
- **Track work with yaks**: [Your First Yak](yak-shaving.md)
- **Learn the TDD approach to skills**: Load the `writing-skills` skill in your agent
