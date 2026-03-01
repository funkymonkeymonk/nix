# Tasks Reference

Tasks are defined in `devenv.nix` and provide common operations.

## Running Tasks

```bash
devenv tasks run <task-name>
```

Or use shell aliases:
```bash
dt <task-name>    # Run any task
dtl               # List all tasks
```

## Shell Aliases

| Alias | Task | Description |
|-------|------|-------------|
| `dt` | `devenv tasks run` | Run any task |
| `dtr` | `devenv tasks run` | Run any task |
| `dtl` | `devenv tasks list` | List all tasks |
| `t` | `test:run` | Quick validation |
| `tq` | `test:quick` | Quick syntax checks |
| `tf` | `test:full` | Full cross-platform tests |
| `s` | `system:switch` | Apply configuration |
| `q` | `quality:check` | Run quality checks |
| `b` | `nix:build` | Build configurations |
| `i` | `dev:ide` | Launch IDE environment |

## System Configuration

| Task | Description |
|------|-------------|
| `system:switch` | Apply configuration (auto-detects platform/hostname) |
| `system:init` | Initial nix-darwin setup (macOS, first-time) |

## Testing

| Task | Description |
|------|-------------|
| `test:run` | Run quick validation |
| `test:quick` | Quick syntax and lint checks (~30s) |
| `test:full` | Full cross-platform validation (5-10min) |
| `test:darwin-only` | Test only Darwin configurations |
| `test:nixos-only` | Test only NixOS configurations |

## Code Quality

| Task | Description |
|------|-------------|
| `quality:check` | Format, deadnix, statix, yamllint |

## Build

| Task | Description |
|------|-------------|
| `nix:build` | Build all configurations (dry-run) |
| `nix:build:darwin` | Build Darwin configurations |
| `nix:build:nixos` | Build NixOS configurations |

## CI Pipeline

| Task | Description |
|------|-------------|
| `ci:quick` | Fast checks (~30s): lint only |
| `ci:lint` | Formatting and static analysis |
| `ci:format` | Apply formatting fixes (alejandra) |
| `ci:flake-check` | Check flake structure |
| `ci:validate` | Full validation (test:full) |
| `ci:validate:darwin` | Darwin configurations only |
| `ci:validate:nixos` | NixOS configurations only |
| `ci:pr` | Full PR pipeline (lint + validate) |
| `ci:local` | Platform-aware local checks |

## Documentation

| Task | Description |
|------|-------------|
| `docs:update` | Update and validate documentation |
| `docs:validate` | Validate structure only |
| `docs:generate` | Generate reference docs only |

## Development Environment

| Task | Description |
|------|-------------|
| `dev:ide` | Launch zellij IDE (yazi, helix, opencode) |
| `dev:pr-review` | Launch PR review dashboard (gh-dash) |

## Flake Management

| Task | Description |
|------|-------------|
| `flake:update` | Update nix flake inputs |
| `devenv:update` | Update devenv lock file |

## Agent Skills

| Task | Description |
|------|-------------|
| `agent-skills:status` | Check skills installation status |
| `agent-skills:update` | Update skills from superpowers |
| `agent-skills:validate` | Validate skills format |

## Git Remote

| Task | Description |
|------|-------------|
| `git:set-remote-ssh` | Switch to SSH remote |
| `git:set-remote-https` | Switch to HTTPS remote |

## Cachix

| Task | Description |
|------|-------------|
| `cachix:push` | Build and push current host to Cachix |
| `cachix:push:all` | Build and push all platform configs |

## MicroVM

| Task | Description |
|------|-------------|
| `microvm:build` | Build microvm image |
| `microvm:run` | Run dev-vm (Linux only) |
| `microvm:test` | Validate microvm configuration |

## Task Details

### system:switch

Auto-detects platform and hostname. Hostname mappings:
- `wweaver`, `Will-Stride-MBP` -> `wweaver`
- `MegamanX` -> `MegamanX`

Uses 1Password for sudo password retrieval on macOS.

### dev:ide

Launches zellij with configurable tools:
- `$FILE_MANAGER` (default: yazi)
- `$EDITOR` (default: helix)
- `$AGENT` (default: opencode)

Set `WITH_PR=1` for PR review layout.

### cachix:push

Requires 1Password with token at `op://Private/Cachix/Auth Token`.

## Git Hooks

Pre-commit hooks run automatically:
- `alejandra` - Nix formatting
- `statix` - Static analysis
- `deadnix` - Dead code detection
- `yamllint` - YAML validation

Pre-push hooks:
- `docs-update` - Documentation validation
