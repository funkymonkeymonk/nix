# Skills Reference

Agent skills are defined in `modules/home-manager/skills/manifest.nix` and installed to `~/.config/opencode/skills/`.

## Available Skills

| Skill | Description | Roles |
|-------|-------------|-------|
| `brainstorming` | Use when creating or developing, before writing code or implementation plans - refines rough ideas into fully-formed designs through collaborative questioning, alternative exploration, and incremental validation. Don't use during clear 'mechanical' processes | creative, opencode, claude, pi |
| `condition-based-waiting` | Use when tests have race conditions, timing dependencies, or inconsistent pass/fail behavior - replaces arbitrary timeouts with condition polling to wait for actual state changes, eliminating flaky tests from timing guesses | opencode, claude, pi |
| `creating-user-manual` | Use when creating a personal user manual, manager README, or working-with-me document. Use when someone wants to document their working style, communication preferences, or collaboration patterns for colleagues | opencode, claude, pi |
| `defense-in-depth` | Use when invalid data causes failures deep in execution, requiring validation at multiple system layers - validates at every layer data passes through to make bugs structurally impossible | opencode, claude, pi |
| `devenv` | Use when working with devenv developer environments. Covers setup, packages, scripts, tasks, processes, services, git-hooks, and file generation. Use when initializing devenv, adding packages, configuring services like postgres/redis, running processes, or troubleshooting devenv issues | opencode, claude, pi |
| `diataxis-docs` | Use when updating, rewriting, or auditing documentation to follow the Diataxis framework | creative, opencode, claude, pi |
| `dispatching-parallel-agents` | Use when facing 3+ independent failures that can be investigated without shared state or dependencies - dispatches multiple agents to investigate and fix independent problems concurrently | opencode, claude, pi |
| `executing-plans` | Use when partner provides a complete implementation plan to execute in controlled batches with review checkpoints - loads plan, reviews critically, executes tasks in batches, reports for review between batches | opencode, claude, pi |
| `innersource-pr-haiku` | Use when given a GitHub PR link and asked to thank a contributor with a haiku and approve the PR | opencode, claude, pi, work |
| `iterating-nix-embedded-scripts` | Use when iterating on shell scripts embedded in Nix modules via writeShellScriptBin, writeShellApplication, writeScriptBin, or writeText — avoids slow build/switch cycles for every edit | opencode, claude, pi |
| `jj` | Use Jujutsu (jj) for version control. Treats pushed commits as immutable; every PR update adds a single new commit on top of the remote tip (no force pushes). Covers workflow, commits, bookmarks with Conventional Branch naming, pushing to GitHub, merge-based sync, stacked PRs, and workspaces for multi-project isolation | opencode, claude, pi |
| `nix-adding-services` | Use when adding a new service to this Nix flake. Covers the full lifecycle: package from source (Node/Rust/Python), service module, options, secrets, home-manager config, tests, target wiring, and validation | opencode, claude, pi |
| `nix-darwin-launchd-debugging` | Use when debugging nix-darwin launchd services that fail to start, exit with non-zero, or don't reload on switch. Covers EX_CONFIG, $HOME expansion trap, daemon vs user.agent, and manual plist reloading | opencode, claude, pi |
| `nix-hf-models` | Use when pre-downloading HuggingFace models into the Nix store for local inference. Covers hf download CLI, fixed-output derivations, hash computation, and CDN/auth issues | opencode, claude, pi |
| `nix-opnix-secrets` | Use when managing 1Password secrets via Nix on nix-darwin. Covers mkOpnixSecretsGeneric, programs.onepassword-secrets, activation script ordering, and runtime patching of config files | opencode, claude, pi |
| `open-url-new-window` | Use when the user asks to open a URL in a new browser window (not a new tab), or when opening documentation/references on macOS without disrupting their current browser session | opencode, claude, pi |
| `prd-review` | Use when reviewing a PRD before or during Ralph Loop execution, checking story completion status, or validating story structure and dependencies in a prd.json file | opencode, claude, pi |
| `ralph-specs` | Use when planning features for autonomous AI implementation, converting ideas into Ralph Loop PRDs, or breaking work into atomic user stories for unattended agent execution | opencode, claude, pi |
| `receiving-code-review` | Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically questionable - requires technical rigor and verification, not performative agreement or blind implementation | opencode, claude, pi |
| `refining-specs` | Use when a specification has open questions requiring research, technical decisions, or user input to resolve | opencode, claude, pi |
| `requesting-code-review` | Use when completing tasks, implementing major features, or before merging to verify work meets requirements - dispatches a code-reviewer subagent to review implementation against plan or requirements before proceeding | opencode, claude, pi |
| `root-cause-tracing` | Use when errors occur deep in execution and you need to trace back to find the original trigger - systematically traces bugs backward through call stack, adding instrumentation when needed, to identify source of invalid data or incorrect behavior | opencode, claude, pi |
| `subagent-driven-development` | Use when executing implementation plans with independent tasks in the current session - dispatches fresh subagent for each task with code review between tasks, enabling fast iteration with quality gates | opencode, claude, pi |
| `systematic-debugging` | Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes - four-phase framework (root cause investigation, pattern analysis, hypothesis testing, implementation) that prevents guess-and-check debugging | opencode, claude, pi |
| `test-driven-development` | Use when implementing any feature or bugfix, before writing implementation code - write the test first, watch it fail, write minimal code to pass; ensures tests actually verify behavior by requiring failure first | opencode, claude, pi |
| `testing-anti-patterns` | Use when writing or changing tests, adding mocks, or tempted to add test-only methods to production code - prevents testing mock behavior, production pollution with test-only methods, and mocking without understanding dependencies | opencode, claude, pi |
| `verification-before-completion` | Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always | opencode, claude, pi |
| `writing-plans` | Use when design is complete and you need detailed implementation tasks for engineers with zero codebase context - creates comprehensive implementation plans with exact file paths, complete code examples, and verification steps assuming engineer has minimal domain knowledge | opencode, claude, pi |
| `writing-skills` | Use when creating new skills, editing existing skills, or verifying skills work before deployment in this repository | creative, opencode, claude, pi |
| `yak-shaving` | Use when tracking, planning, implementing, or reviewing work using yx (yaks) with the autonomous /shave loop, or when multiple agents need to coordinate on shared tasks | opencode, claude, pi |
| `zellij` | Zellij terminal multiplexer — creating KDL layouts, managing sessions via CLI, and running commands without disrupting the user's workspace | opencode, claude, pi |

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
