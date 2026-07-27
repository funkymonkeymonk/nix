# Skills Reference

Agent skills are defined in `modules/home-manager/skills/manifest.nix`.

## Available Skills

| Skill | Description | Roles |
|-------|-------------|-------|
| `brainstorming` | Help turn ideas into fully formed designs through collaborative dialogue | developer, creative |
| `debugging` | Systematic debugging approach for bugs, test failures, unexpected behavior | developer |
| `diataxis-docs` | Use when updating, rewriting, or auditing documentation to follow the Diataxis framework | developer, creative, opencode, claude |
| `iterating-nix-embedded-scripts` | Use when iterating on shell scripts embedded in Nix modules | developer, opencode, claude |
| `jj` | Use Jujutsu (jj) for version control — workflow, commits, bookmarks, stacked PRs, workspaces | developer, opencode, claude |
| `nix-adding-services` | Use when adding a new service to this Nix flake | developer, opencode, claude, pi |
| `nix-darwin-launchd-debugging` | Use when debugging nix-darwin launchd services that fail to start | developer, opencode, claude, pi |
| `nix-hf-models` | Use when pre-downloading HuggingFace models into the Nix store | developer, opencode, claude, pi |
| `nix-opnix-secrets` | Use when managing 1Password secrets via Nix on nix-darwin | developer, opencode, claude, pi |
| `openclaw` | Guidelines for working with OpenClaw AI assistant configuration and deployment | developer, opencode, claude |
| `prd-review` | Display PRD files in human-readable format for review and status tracking | developer, opencode, claude |
| `ralph-specs` | Write specifications optimized for Ralph Loop autonomous agent execution | developer, opencode, claude |
| `receiving-code-review` | Process code review feedback with technical rigor | developer, workstation |
| `refining-specs` | Use when a specification has open questions requiring research or decisions | developer, opencode, claude |
| `requesting-code-review` | Properly request code reviews and prepare PRs | developer, workstation |
| `tdd` | Test-driven development workflow for implementing features and bugfixes | developer |
| `using-superpowers` | Access and use available skills for the current task | opencode, claude |
| `verification-before-completion` | Run verification commands before claiming work is complete | developer |
| `watch-ci-jobs` | Monitor GitHub Actions CI jobs with intelligent adaptive polling | developer, workstation |
| `writing-plans` | Create detailed implementation plans from specs and requirements | developer |
| `writing-skills` | Use when creating, editing, or verifying skills before deployment | developer, creative, opencode, claude |
| `yak-shaving` | Track, plan, implement, or review work using yx (yaks) with the `/shave` loop | developer, opencode, claude, pi |
| `zellij` | Zellij terminal multiplexer — KDL layouts, session management via CLI | developer, opencode, claude |

## Skill Structure

Each skill contains:

```
skills/<skill-name>/
└── SKILL.md          # Skill definition with frontmatter
```

Some skills also bundle slash commands (e.g. `jj`'s `/finish`, `/pr`, `/push`;
`yak-shaving`'s `/shave`) via a `commands` field in their manifest entry.

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

Skills are installed differently depending on the agent and source type:

- **opencode / claude-code — internal + superpowers skills**: installed
  declaratively via home-manager's native `programs.opencode.skills` /
  `programs.claude-code.skills` options. `modules/home-manager/opencode.nix`
  and `modules/home-manager/claude-code.nix` resolve the manifest (filtered
  by `myConfig.skills.enabledRoles`) into an attrset of skill-name →
  directory path using the shared `mkFullSkillDirs` helper in
  `modules/home-manager/lib.nix`, and assign it directly to the option.
- **pi — internal + superpowers skills**: there is no native
  `programs.pi-coding-agent` module upstream, so
  `modules/home-manager/pi-coding-agent.nix` installs the same resolved
  skill set as plain `home.file` entries under `.pi/agent/skills/<name>/`.
- **All agents — external skills** (`source.type = "external"`): fetched
  over the network at activation time via `npx skills add`, since this
  can't be expressed as a static Nix value.
  `modules/home-manager/skills/install.nix` owns this mechanism exclusively.

## Skill Locations

- **Internal skills**: `modules/home-manager/skills/internal/`
- **External (bundled) skills**: `modules/home-manager/skills/external/`
- **Installed location (opencode)**: `~/.config/opencode/skills/`
- **Installed location (claude-code)**: `~/.claude/skills/`
- **Installed location (pi)**: `~/.pi/agent/skills/`

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
  autoLoad = false;          # Optional: concatenate SKILL.md into every session's context
  commands = {                # Optional: bundled slash commands
    path = ./internal/skill-name/commands;
    list = ["command-name"];
  };
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
