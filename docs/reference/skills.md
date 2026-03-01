# Skills Reference

Agent skills are defined in `modules/home-manager/skills/manifest.nix` and installed to `~/.config/opencode/skills/`.

## Available Skills

| Skill | Description | Roles |
|-------|-------------|-------|
| `brainstorming` | Collaborative design dialogue | developer, creative |
| `debugging` | Systematic debugging approach | developer |
| `diataxis-docs` | Documentation restructuring (Diataxis framework) | developer, creative, llm-client, llm-claude |
| `jj` | Jujutsu version control | developer, llm-client, llm-claude |
| `prd-review` | Display PRD files for review and status tracking | developer, llm-client, llm-claude |
| `ralph-specs` | Write specs for Ralph Loop autonomous agent | developer, llm-client, llm-claude |
| `receiving-code-review` | Process review feedback | developer, workstation |
| `requesting-code-review` | Prepare and request reviews | developer, workstation |
| `tdd` | Test-driven development workflow | developer |
| `using-superpowers` | Access available skills | llm-client, llm-claude |
| `verification-before-completion` | Pre-completion verification | developer |
| `writing-plans` | Implementation plan creation | developer |
| `writing-skills` | Skill documentation and creation | developer, creative, llm-client, llm-claude |

## Skill Structure

```
skills/<skill-name>/
└── SKILL.md          # Skill definition with frontmatter
```

### SKILL.md Format

```markdown
---
name: skill-name
description: Brief description
---

# Skill Name

## Overview
...

## When to Use
...

## Process
...
```

## Skill Sources

| Type | Location | Description |
|------|----------|-------------|
| `internal` | `modules/home-manager/skills/internal/` | Defined in this repo |
| `external` | `modules/home-manager/skills/external/` | Adapted from external sources |
| `superpowers` | From flake input | Skills from superpowers repo |

## Installation

Skills install automatically based on enabled roles:

1. `mkBundleModule` sets `myConfig.skills.enabledRoles`
2. `skills/install.nix` filters manifest by roles
3. Matching skills are symlinked via home-manager
4. Dependencies are resolved and included

## Manifest Entry

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
