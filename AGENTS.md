# Agents Guide

Guide for AI agents working with this Nix system configuration repository.

## Repository Overview

This repository manages the configuration of computers via Nix flakes. **Agents should only modify Nix configuration files - never directly change computer configurations.**

## Architecture

- **Modules**: Reusable configuration logic (`modules/`)
- **Bundles**: Package collections by role (`bundles.nix`)
- **Targets**: Machine-specific configurations (`targets/`)
- **Options**: Type-safe configuration (`modules/common/options.nix`)

## Directory Structure

```
.
├── .github/                    # GitHub Actions workflows
├── modules/
│   ├── common/                 # Shared: options, users, shell, onepassword
│   ├── home-manager/           # User environment
│   │   └── skills/             # Agent skills management
│   └── nixos/                  # Linux-specific modules
├── targets/                    # Machine configurations
├── os/                         # Platform OS configurations
├── bundles.nix                 # Role definitions
├── flake.nix                   # Main flake with helpers
└── devenv.nix                  # Tasks and dev environment
```

## Tasks

```bash
devenv tasks list              # List all tasks
devenv tasks run <task>        # Run a task
```

### Key Tasks

| Task | Description |
|------|-------------|
| `check:all` | Run all checks (lint + platform builds) |
| `check:lint` | Lint only |
| `build:darwin` | Build Darwin configurations (dry-run) |
| `build:nixos` | Build NixOS configurations (dry-run) |
| `system:switch` | Apply configuration |

### Shell Aliases

| Alias | Task |
|-------|------|
| `s` | `system:switch` |
| `q` | `check:all` |
| `b` | `build:all` |
| `i` | `dev:ide` |

## Working with This Repository

### Before Changes
1. Run `devenv tasks run check:lint` for fast feedback
2. Use `devenv shell` for proper tooling

### Making Changes
1. Modify files as needed
2. Run `devenv tasks run check:all` for validation
3. Commit with conventional commit messages

### Adding Features

| Feature | Steps |
|---------|-------|
| New Machine | Create `targets/<name>/`, add to `flake.nix` using `mkDarwinHost` or `mkNixosHost` |
| New Role | Add to `bundles.nix` under `roles` |
| New Module | Create in `modules/` subdirectory |
| New Option | Add to `modules/common/options.nix` |

## Roles (bundles.nix)

| Role | Description |
|------|-------------|
| `base` | Essential packages and shell |
| `developer` | Development tools |
| `creative` | Media tools |
| `desktop` | Desktop applications |
| `workstation` | Work tools |
| `entertainment` | Entertainment apps |
| `gaming` | Gaming tools |
| `agent-skills` | AI skills management |
| `llm-client` | OpenCode + rtk |
| `llm-claude` | Claude Code |
| `llm-host` | Ollama |

## Helper Functions (flake.nix)

| Helper | Purpose |
|--------|---------|
| `mkUser` | Create user configuration with defaults |
| `mkNixHomebrew` | Create homebrew config for Darwin |
| `mkBundleModule` | Create bundle from role list |
| `mkDarwinHost` | Create complete Darwin host |
| `mkNixosHost` | Create complete NixOS host |
| `mkMicrovm` | Create microvm configuration |

## Agent Skills

Skills auto-install when roles like `developer`, `llm-client`, or `llm-claude` are active.

**Location:** `~/.config/opencode/skills/`

### Adding Skills

1. Create `modules/home-manager/skills/internal/skill-name/SKILL.md`
2. Register in `modules/home-manager/skills/manifest.nix`
3. Rebuild system

## Jujutsu (jj) Version Control

If `.jj/` directory exists:
1. Use `jj` skill for all version control
2. Run `jj status` before any operation
3. Use `jj new` before starting work
4. Use `jj describe` for commit messages
5. Never mix git and jj commands

## Platform Support

- **macOS**: nix-darwin (aarch64-darwin)
- **Linux**: NixOS (x86_64-linux)

### Cross-Platform Validation

Tests are platform-specific:
- `test:darwin` on macOS
- `test:nixos` on Linux

CI runs both on separate runners.

## Code Style

- Use alejandra formatter (`quality:check`)
- Remove dead code (deadnix)
- Follow existing patterns
- Conventional commits: `feat:`, `fix:`, `docs:`

## RTK Token Optimization

Use RTK-prefixed commands for token-efficient output:

| Standard | RTK | Savings |
|----------|-----|---------|
| `git status` | `rtk git status` | ~80% |
| `git diff` | `rtk git diff` | ~75% |
| `git log` | `rtk git log` | ~80% |

Check savings: `rtk gain`
