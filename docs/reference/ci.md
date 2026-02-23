# CI/CD Pipeline

This document describes the CI/CD pipeline for the Nix configuration repository.

## Overview

The CI pipeline uses devenv tasks, allowing it to run identically:
- Locally on any platform (macOS or Linux)
- In GitHub Actions

## Pipeline Stages

### Stage 1: Quick Checks (~30 seconds)

Fast feedback loop for immediate validation:

- **Flake Check**: Validates flake structure and syntax
- **Formatting**: Checks code formatting with `alejandra`
- **Dead Code**: Detects unused code with `deadnix`
- **Static Analysis**: Runs `statix` for common issues

```bash
# Run locally
devenv tasks run ci:quick
```

### Stage 2: Platform Validation (5-10 minutes)

Comprehensive validation of all configurations:

- **Darwin**: Validates `wweaver` and `MegamanX` configurations
- **NixOS**: Validates `drlight` and `zero` configurations
- **Microvm**: Validates `dev-vm` configuration

```bash
# Run all validations
devenv tasks run ci:validate

# Run platform-specific
devenv tasks run ci:validate:darwin
devenv tasks run ci:validate:nixos

# Full PR pipeline
devenv tasks run ci:pr
```

### Stage 3: Full Builds (Main branch only)

Actual builds with Cachix push:

- **Darwin builds**: Run on native macOS runners
- **NixOS builds**: Run on Linux runners

### Stage 4: Publish (Main branch only)

- **FlakeHub**: Publishes flake to private FlakeHub account

## Local Development

### Quick Check (Fast Feedback)

```bash
# Fastest feedback loop
devenv tasks run ci:quick
```

### Full Validation

```bash
# Complete PR validation
devenv tasks run ci:pr
```

### Platform-Aware Local Check

```bash
# Automatically detects platform and runs appropriate checks
devenv tasks run ci:local
```

### Formatting

```bash
# Check formatting
devenv tasks run ci:lint

# Apply formatting fixes
devenv tasks run ci:format
```

## Running NixOS Validation on macOS

The CI pipeline validates NixOS configurations using `nix eval` and `nix build --dry-run`, which work regardless of host platform. For more comprehensive NixOS testing with actual VM execution:

1. **Using Colima** (recommended):
   ```bash
   colima start --arch x86_64 --vm-type vz
   colima ssh
   cd /path/to/nix
   devenv tasks run microvm:run
   ```

2. **Using devenv microvm tasks**:
   ```bash
   devenv tasks run microvm:test  # Validate configuration
   devenv tasks run microvm:build # Build VM image (Linux only)
   devenv tasks run microvm:run   # Run VM (Linux only)
   ```

## Available CI Tasks

| Task | Description |
|------|-------------|
| `ci:quick` | Fast checks (lint, format, flake check) |
| `ci:lint` | Formatting and linting only |
| `ci:format` | Apply formatting fixes |
| `ci:validate:darwin` | Validate Darwin configurations |
| `ci:validate:nixos` | Validate NixOS configurations |
| `ci:validate` | All validation checks |
| `ci:pr` | Full PR pipeline (quick + validate) |
| `ci:local` | Platform-aware local validation |

## GitHub Actions Workflow

The workflow in `.github/workflows/nix-ci.yml` orchestrates:

```
PR/Push to any branch:
  ┌─────────────┐
  │   quick     │  (~30s) Lint, format, flake check
  └──────┬──────┘
         │
    ┌────┴────┐
    │ parallel │
    ▼         ▼
┌──────────┐ ┌──────────┐
│ validate │ │ validate │
│  darwin  │ │  nixos   │
└────┬─────┘ └────┬─────┘
     │            │
     └────────────┘

Push to main:
  ┌─────────────┐
  │   (above)   │
  └──────┬──────┘
         │
    ┌────┴────┐
    │ parallel │
    ▼         ▼
┌──────────┐ ┌──────────┐
│  build   │ │  build   │
│  darwin  │ │  nixos   │  + Cachix push
└────┬─────┘ └────┬─────┘
     │            │
     └─────┬──────┘
           ▼
    ┌─────────────┐
    │  publish    │
    │  flakehub   │
    └─────────────┘
```

## Secrets Required

| Secret | Purpose |
|--------|---------|
| `CACHIX_AUTH_TOKEN` | Push builds to Cachix cache |
| (OIDC) | FlakeHub uses GitHub OIDC for authentication |
