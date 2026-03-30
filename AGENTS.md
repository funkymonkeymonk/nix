# Agents Guide

Guide for AI agents working with this Nix system configuration repository.

## Repository Overview

This repository manages the configuration of computers via Nix flakes. **Agents should only modify Nix configuration files - never directly change computer configurations.**

## Architecture

- **Modules**: Reusable configuration logic (`modules/`)
- **Roles**: Modular role configurations (`modules/roles/`)
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
│   ├── roles/                  # Role modules (one per role)
│   └── nixos/                  # Linux-specific modules
├── targets/                    # Machine configurations
├── os/                         # Platform OS configurations
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

### Testing Best Practices (CRITICAL)

**Always test locally before pushing to CI.** This catches errors early and saves time:

#### Required Local Tests (Run These Before Every Push)

```bash
# 1. Fast lint check (catches formatting and syntax errors)
devenv tasks run check:lint

# 2. Test Darwin configs can be evaluated (catches module errors)
# Run this on macOS - it validates all Darwin configurations without building
devenv tasks run test:darwin-eval

# 3. Test NixOS configs can be evaluated (catches module errors)
# Run this on any platform - validates module structure without full builds
devenv tasks run test:nixos-eval

# 4. Run all foundation tests
devenv tasks run test:all
```

#### What These Tests Catch

| Test | Catches |
|------|---------|
| `check:lint` | Formatting errors, dead code, syntax issues |
| `test:darwin-eval` | Missing options on Darwin (e.g., `programs.zoxide`), module import errors |
| `test:nixos-eval` | Missing options on NixOS (e.g., `home-manager.users`), module import errors |
| `test:all` | Package availability, option definitions |

#### Common Module Errors to Avoid

1. **Platform-Specific Options**: Options like `programs.zoxide` or `environment.sessionVariables` don't exist on all platforms. Check if options exist before using them:
   ```nix
   # Good: Check if option exists
   config = lib.optionalAttrs (builtins.hasAttr "zoxide" options.programs) {
     programs.zoxide.enable = true;
   };
   
   # Bad: Assumes option exists everywhere
   programs.zoxide.enable = true;
   ```

2. **home-manager References**: Don't reference `home-manager` options when home-manager module isn't imported:
   ```nix
   # Good: Guard home-manager config
   homeManagerAvailable = builtins.hasAttr "home-manager" options;
   config = lib.mkIf homeManagerAvailable {
     home-manager.users = ...;
   };
   ```

3. **Using pkgs in let bindings**: This can cause infinite recursion. Use `config.myConfig.isDarwin` instead of checking `pkgs.stdenv.hostPlatform`.

### Before Changes
1. Run `devenv tasks run check:lint` for fast feedback
2. Run platform-specific eval tests (`test:darwin-eval` or `test:nixos-eval`)
3. Use `devenv shell` for proper tooling

### Making Changes
1. Modify files as needed
2. Run local tests (lint + platform eval tests)
3. Run `devenv tasks run check:all` for validation
4. Commit with conventional commit messages

### Adding Features

| Feature | Steps |
|---------|-------|
| New Machine | Create `targets/<name>/`, add to `flake.nix` |
| New Role | Create `modules/roles/<name>.nix`, add enable option to `modules/common/options.nix` |
| New Module | Create in `modules/` subdirectory |
| New Option | Add to `modules/common/options.nix` |

## Roles (modules/roles/)

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

## NixOS Rebuild Commands

When deploying to NixOS systems:

```bash
# Standard rebuild (always use --impure for non-CI environments)
sudo nixos-rebuild switch --flake github:funkymonkeymonk/nix#<hostname> --impure

# Example for type-server
sudo nixos-rebuild switch --flake github:funkymonkeymonk/nix#type-server --impure
```

**Important**: Always use `--impure` flag for manual deployments. This repository uses nixos-facter for hardware detection and disposable environments that require impure evaluation. Only CI uses pure evaluation.

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
