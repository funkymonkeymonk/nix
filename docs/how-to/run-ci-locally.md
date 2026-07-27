---
title: "Run CI Locally"
description: "How to run CI validation on your local machine before pushing"
type: how-to
audience: both
automation-ready: true
last-reviewed: 2026-07-27
---

# Run CI Locally

This guide shows you how to run CI validation on your local machine.

## Quick Validation (~1 second)

For fast feedback during development:

```bash
devenv tasks run check:lint
```

This runs:
- Nix formatting check (alejandra)
- Dead code detection (deadnix)
- Static analysis (statix)
- YAML linting (yamllint)

## Full Validation

Before opening a PR:

```bash
devenv tasks run test:eval    # gates the build — must pass first
devenv tasks run test:all     # eval + a curated set of build checks
```

`test:all` runs `test:eval` internally, then builds the checks used most
often in day-to-day development (packages, options, roles, skills, email,
sketchybar, 1Password, vane, opencode, aerospace, workspace-switch, LLM
client, module coverage). It does **not** build every single
`flake.checks` entry — see [Tasks Reference](../reference/tasks.md) for the
full list, or run `nix flake check --no-build` to eval-check everything.

## Platform-Specific Validation

`test:eval` and `test:all` are platform-aware — they evaluate whichever
Darwin/NixOS configurations are reachable from your current platform. There
is no separate `build:darwin` / `build:nixos` task; CI validates both
platforms on separate runners (see below).

## Fixing Issues

### Formatting Problems

```bash
# See what needs formatting (also runs deadnix + statix + yamllint)
devenv tasks run check:lint

# Auto-fix formatting only
nix run nixpkgs#alejandra -- <path>
```

### Dead Code Warnings

`deadnix` identifies unused variables. Remove them or prefix with `_`:

```nix
# Before (warning)
{ pkgs, lib, ... }: { }

# After (if lib is unused)
{ pkgs, _lib, ... }: { }
```

### Static Analysis Issues

`statix` catches common Nix anti-patterns. Review its suggestions and apply fixes.

## Cross-Platform Testing

CI validates both platforms using separate runners:

| Runner | What Gets Validated |
|---------------|---------------------|
| macOS | Darwin configs (dry-run build) |
| Linux | NixOS configs (dry-run build) |

## Shell Commands

After entering the devenv shell, these shortcuts are available:

```bash
s          # devenv tasks run system:switch (workspace-aware)
dt <task>  # devenv tasks run <task>
dtl        # devenv tasks list
```

> **See also:** [Tasks Reference](../reference/tasks.md) for the full task list
