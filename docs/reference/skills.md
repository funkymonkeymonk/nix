# Skills Reference

Agent skills are defined in `modules/home-manager/skills/manifest.nix` and installed to `~/.config/opencode/skills/`.

## Available Skills

| Skill | Description | Roles |
|-------|-------------|-------|
| `brainstorming` | Collaborative design dialogue | developer, creative |
| `debugging` | Systematic debugging approach | developer |
| `diataxis-docs` | Documentation restructuring (Diataxis framework) | developer, creative, llm-client, llm-claude |
| `jj` | Jujutsu version control | developer, llm-client, llm-claude |
| `receiving-code-review` | Process review feedback | developer, workstation |
| `requesting-code-review` | Prepare and request reviews | developer, workstation |
| `tdd` | Test-driven development workflow | developer |
| `using-superpowers` | Access available skills | llm-client, llm-claude |
| `verification-before-completion` | Pre-completion verification | developer |
| `writing-plans` | Implementation plan creation | developer |
| `writing-skills` | Documentation and skill writing | developer, creative, llm-client, llm-claude |

## Skill Structure

Each skill contains:

```
skills/<skill-name>/
└── SKILL.md          # Skill definition with frontmatter
```

### SKILL.md Format

```markdown
---
name: skill-name
description: Brief description of what the skill does
---

# Skill Name

## Overview
...

## When to Use
...

## Process
...
```

## Installation

Skills are installed automatically based on enabled roles:

1. `flake.nix` sets `myConfig.skills.enabledRoles`
2. `skills/install.nix` filters manifest by roles
3. Matching skills are symlinked via home-manager

## Skill Locations

- **Internal skills**: `modules/home-manager/skills/internal/`
- **External skills**: `modules/home-manager/skills/external/`
- **Installed location**: `~/.config/opencode/skills/`

## Manifest Entry Format

```nix
"skill-name" = {
  description = "Brief description";
  roles = ["developer" "creative"];
  source = {
    type = "internal";       # or "external" or "superpowers"
    path = ./internal/skill-name;
  };
  deps = [];                 # Skill dependencies
};
```

## Commands

```bash
# Check installation status
devenv tasks run agent-skills:status

# Validate skill format
devenv tasks run agent-skills:validate

# List installed skills
skills-list
```
