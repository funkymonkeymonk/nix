---
title: "Run CI Locally"
description: "How to run CI validation on your local machine before pushing"
type: how-to
audience: both
automation-ready: true
last-reviewed: 2026-04-06
---

# Run CI Locally

This guide shows you how to run CI validation on your local machine.

## Quick Validation (~30 seconds)

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
devenv tasks run check:all
```

This includes:
- Lint checks (`check:lint`)
- nix-unit eval tests (`check:unit`)
- Configuration evaluation (`test:eval`)

## Platform-Specific Validation

### Configuration Evaluation

```bash
devenv tasks run test:eval
```

Evaluates all NixOS and Darwin configurations without building. This is the fastest way to catch option errors and missing references.

## Fixing Issues

### Formatting Problems

```bash
# See what needs formatting
devenv tasks run check:lint

# Auto-fix formatting
alejandra .
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

## Shell Aliases

After entering the devenv shell, these shortcuts are available:

```bash
q       # devenv tasks run check:all
t       # devenv tasks run test:all
```

> **See also:** [Tasks Reference](../reference/tasks.md) for the full task list
