# Skills Reference

Agent skills are defined in `modules/home-manager/skills/manifest.nix` and installed to `~/.config/opencode/skills/`.

## Available Skills

| Skill | Description | Roles |
|-------|-------------|-------|
| `brainstorming` | Use when creating or developing, before writing code or implementation plans | developer, creative, opencode, claude, pi |
| `condition-based-waiting` | Use when tests have race conditions or timing dependencies — replaces arbitrary timeouts with condition polling | developer, opencode, claude, pi |
| `creating-user-manual` | Use when creating a personal user manual, manager README, or working-with-me document | developer, opencode, claude |
| `defense-in-depth` | Use when invalid data causes failures deep in execution — validates at every layer | developer, opencode, claude, pi |
| `devenv` | Use when working with devenv developer environments — setup, packages, scripts, tasks, processes, services, git-hooks | developer, opencode, claude |
| `diataxis-docs` | Use when updating, rewriting, or auditing documentation to follow the Diataxis framework | developer, creative, opencode, claude |
| `dispatching-parallel-agents` | Use when facing 3+ independent failures investigable without shared state | developer, opencode, claude, pi |
| `executing-plans` | Use when a partner provides a complete implementation plan to execute in batches | developer, opencode, claude, pi |
| `innersource-pr-haiku` | Use when given a GitHub PR link and asked to thank a contributor with a haiku and approve the PR | developer, workstation |
| `iterating-nix-embedded-scripts` | Use when iterating on shell scripts embedded in Nix modules via writeShellScriptBin, writeShellApplication, writeScriptBin, or writeText — avoids slow build/switch cycles for every edit | developer, opencode, claude |
| `jj` | Use Jujutsu (jj) for version control. Treats pushed commits as immutable; every PR update adds a single new commit on top of the remote tip (no force pushes). Covers workflow, commits, bookmarks with Conventional Branch naming, pushing to GitHub, merge-based sync, stacked PRs, and workspaces for multi-project isolation | developer, opencode, claude |
| `nix-adding-services` | Use when adding a new service to this Nix flake. Covers the full lifecycle: package from source (Node/Rust/Python), service module, options, secrets, home-manager config, tests, target wiring, and validation | developer, opencode, claude, pi |
| `nix-darwin-launchd-debugging` | Use when debugging nix-darwin launchd services that fail to start, exit with non-zero, or don't reload on switch. Covers EX_CONFIG, $HOME expansion trap, daemon vs user.agent, and manual plist reloading | developer, opencode, claude, pi |
| `nix-hf-models` | Use when pre-downloading HuggingFace models into the Nix store for local inference. Covers hf download CLI, fixed-output derivations, hash computation, and CDN/auth issues | developer, opencode, claude, pi |
| `nix-opnix-secrets` | Use when managing 1Password secrets via Nix on nix-darwin. Covers mkOpnixSecretsGeneric, programs.onepassword-secrets, activation script ordering, and runtime patching of config files | developer, opencode, claude, pi |
| `open-url-new-window` | Use when the user asks to open a URL in a new browser window (not a new tab) on macOS | developer, opencode, claude |
| `prd-review` | Use when reviewing a PRD before or during Ralph Loop execution, checking story completion status, or validating story structure and dependencies | developer, opencode, claude |
| `ralph-specs` | Use when planning features for autonomous AI implementation, converting ideas into Ralph Loop PRDs, or breaking work into atomic user stories | developer, opencode, claude |
| `receiving-code-review` | Use when receiving code review feedback, before implementing suggestions | developer, opencode, claude, pi |
| `refining-specs` | Use when a specification has open questions requiring research, technical decisions, or user input to resolve | developer, opencode, claude |
| `requesting-code-review` | Use when completing tasks or before merging — dispatches a code-reviewer subagent (jj-adapted fork) | developer, opencode, claude, pi |
| `root-cause-tracing` | Use when errors occur deep in execution and you need to trace back to the original trigger | developer, opencode, claude, pi |
| `subagent-driven-development` | Use when executing implementation plans with independent tasks, dispatching a fresh subagent per task | developer, opencode, claude, pi |
| `systematic-debugging` | Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes (jj-adapted fork) | developer, opencode, claude, pi |
| `test-driven-development` | Use when implementing any feature or bugfix, before writing implementation code | developer, opencode, claude, pi |
| `testing-anti-patterns` | Use when writing or changing tests, adding mocks, or tempted to add test-only methods to production code | developer, opencode, claude, pi |
| `verification-before-completion` | Use when about to claim work is complete, fixed, or passing, before committing or creating PRs | developer, opencode, claude, pi |
| `writing-plans` | Use when design is complete and you need detailed implementation tasks for engineers with zero codebase context (jj-adapted fork) | developer, opencode, claude, pi |
| `writing-skills` | Use when creating new skills, editing existing skills, or verifying skills work before deployment | developer, creative, opencode, claude, pi |
| `yak-shaving` | Use when tracking, planning, implementing, or reviewing work using yx (yaks) with the autonomous /shave loop, or when multiple agents need to coordinate on shared tasks | developer, opencode, claude, pi |
| `zellij` | Zellij terminal multiplexer — creating KDL layouts, managing sessions via CLI, and running commands without disrupting the user's workspace | developer, opencode, claude |

`brainstorming` through `verification-before-completion` (except the three
marked "jj-adapted fork") are sourced directly from the `superpowers` flake
input (`github:obra/superpowers`) via `source.type = "superpowers"` — no
local copy to maintain. The three forks were copied and patched because
upstream used git-specific commands; this repo uses jj.

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
# Internal skill (defined in this repo, or a fork of an upstream skill)
"skill-name" = {
  description = "Brief description";
  roles = ["developer" "creative"];
  source = {
    type = "internal";
    path = ./internal/skill-name;
  };
  deps = [];                 # Skill dependencies
};

# Superpowers skill (sourced from the `superpowers` flake input,
# github:obra/superpowers — update the pin with
# `nix flake update --update-input superpowers`)
"skill-name" = {
  description = "Brief description";
  roles = ["developer" "opencode" "claude" "pi"];
  source = {
    type = "superpowers";
    skillName = "skill-name";  # directory name under superpowers' skills/
  };
  deps = [];
};
```

## Commands

```bash
# Check installation status
skills-status

# List installed skills
skills-list
```
