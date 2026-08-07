# Skills Reference

Agent skills are defined in `modules/home-manager/skills/manifest.nix` and installed to `~/.config/opencode/skills/`.

## Available Skills

| Skill | Description | Roles |
|-------|-------------|-------|
| `brainstorming` | Help turn ideas into fully formed designs through collaborative dialogue | developer, creative |
| `debugging` | Systematic debugging approach for bugs, test failures, unexpected behavior | developer |
| `diataxis-docs` | Use when updating, rewriting, or auditing documentation to follow the Diataxis framework | developer, creative, opencode, claude |
| `iterating-nix-embedded-scripts` | Use when iterating on shell scripts embedded in Nix modules via writeShellScriptBin, writeShellApplication, writeScriptBin, or writeText — avoids slow build/switch cycles for every edit | developer, opencode, claude |
| `jj` | Use Jujutsu (jj) for version control. Treats pushed commits as immutable; every PR update adds a single new commit on top of the remote tip (no force pushes). Covers workflow, commits, bookmarks with Conventional Branch naming, pushing to GitHub, merge-based sync, stacked PRs, and workspaces for multi-project isolation | developer, opencode, claude |
| `nix-adding-services` | Use when adding a new service to this Nix flake. Covers the full lifecycle: package from source (Node/Rust/Python), service module, options, secrets, home-manager config, tests, target wiring, and validation | developer, opencode, claude, pi |
| `nix-darwin-launchd-debugging` | Use when debugging nix-darwin launchd services that fail to start, exit with non-zero, or don't reload on switch. Covers EX_CONFIG, $HOME expansion trap, daemon vs user.agent, and manual plist reloading | developer, opencode, claude, pi |
| `nix-hf-models` | Use when pre-downloading HuggingFace models into the Nix store for local inference. Covers hf download CLI, fixed-output derivations, hash computation, and CDN/auth issues | developer, opencode, claude, pi |
| `nix-opnix-secrets` | Use when managing 1Password secrets via Nix on nix-darwin. Covers mkOpnixSecretsGeneric, programs.onepassword-secrets, activation script ordering, and runtime patching of config files | developer, opencode, claude, pi |
| `openclaw` | Guidelines for working with OpenClaw AI assistant configuration and deployment | developer, opencode, claude |
| `prd-review` | Display PRD files in human-readable format for review and status tracking. Shows progress, story details, and flags potential issues | developer, opencode, claude |
| `ralph-specs` | Write specifications optimized for Ralph Loop autonomous agent execution. Covers PRD structure, atomic user stories, and machine-verifiable acceptance criteria | developer, opencode, claude |
| `receiving-code-review` | Process code review feedback with technical rigor | developer, workstation |
| `refining-specs` | Use when a specification has open questions requiring research, technical decisions, or user input to resolve | developer, opencode, claude |
| `requesting-code-review` | Properly request code reviews and prepare PRs | developer, workstation |
| `tdd` | Test-driven development workflow for implementing features and bugfixes | developer |
| `using-superpowers` | Access and use available skills for the current task | opencode, claude |
| `verification-before-completion` | Run verification commands before claiming work is complete | developer |
| `watch-ci-jobs` | Monitor GitHub Actions CI jobs with intelligent polling that adapts to historical run times | developer, workstation |
| `writing-plans` | Create detailed implementation plans from specs and requirements | developer |
| `writing-skills` | Use when creating new skills, editing existing skills, or verifying skills work before deployment | developer, creative, opencode, claude |
| `yak-shaving` | Use when tracking, planning, implementing, or reviewing work using yx (yaks) with the autonomous /shave loop, or when multiple agents need to coordinate on shared tasks | developer, opencode, claude, pi |
| `zellij` | Zellij terminal multiplexer — creating KDL layouts, managing sessions via CLI, and running commands without disrupting the user's workspace | developer, opencode, claude |

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
