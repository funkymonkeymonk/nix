# CI/CD Reference

CI/CD pipelines for validating and building configurations.

## Workflow Files

| File | Purpose | Trigger |
|------|---------|---------|
| `pr-validation.yml` | PR checks | Pull requests |
| `main-build.yml` | Build + cache | Push to main |
| `flake-update.yml` | Dependency updates | Weekly (Fridays 4AM UTC) |
| `opencode.yml` | AI assistant | `/oc` or `/opencode` comments |

## Pipeline Overview

```
Pull Request:
  ┌─────────┐
  │  lint   │  Formatting, deadnix, statix
  └────┬────┘
       │ (parallel)
  ┌────┴────┐
  ▼         ▼
┌────────┐ ┌────────┐
│ darwin │ │ linux  │  Dry-run builds
└────────┘ └────────┘

Push to main:
  ┌─────────────┐     ┌─────────────┐
  │ build-darwin│     │ build-linux │  Full builds
  └──────┬──────┘     └──────┬──────┘
         └──────┬────────────┘
                ▼
         Cachix push
```

## CI Tasks

| Task | Duration | Description |
|------|----------|-------------|
| `ci:quick` | ~30s | Lint checks only |
| `ci:lint` | ~10s | Formatting and static analysis |
| `ci:format` | ~5s | Apply formatting fixes |
| `ci:flake-check` | ~30s | Validate flake structure |
| `ci:validate` | 5-10min | All platform validation |
| `ci:validate:darwin` | 2-5min | Darwin configurations only |
| `ci:validate:nixos` | 2-5min | NixOS configurations only |
| `ci:pr` | 5-10min | Full PR pipeline (lint + validate) |
| `ci:local` | varies | Platform-aware local checks |

## Validated Configurations

### Darwin (macOS)
- `wweaver` - Work laptop
- `MegamanX` - Personal desktop

### NixOS (Linux)
- `drlight` - Server (Jellyfin, Mealie)
- `zero` - Gaming/desktop (NVIDIA)

### Microvm
- `dev-vm` - Development VM (validated via `microvm:test`)

## Quick Checks (ci:lint)

- **Formatting**: `alejandra` - Nix code formatting
- **Dead Code**: `deadnix` - Unused code detection
- **Static Analysis**: `statix` - Common issues and anti-patterns
- **YAML**: `yamllint` - YAML file validation

## Cross-Platform Validation

| Host | Darwin Configs | NixOS Configs |
|------|----------------|---------------|
| macOS | Full build | Eval + dry-run |
| Linux | Eval only | Full build |

## Secrets

| Secret | Purpose |
|--------|---------|
| `CACHIX_AUTH_TOKEN` | Push builds to Cachix |

## Weekly Flake Updates

The `flake-update.yml` workflow:
1. Runs every Friday at 4:00 AM UTC
2. Checks for available updates
3. Validates changes pass `nix flake check`
4. Creates PR with update details
5. Closes superseded PRs

> **See also:** [Run CI Locally](../how-to/run-ci-locally.md)
