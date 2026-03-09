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
- Lint checks
- Platform-specific build validation (Darwin on macOS, NixOS on Linux)

## Platform-Specific Validation

### Darwin Only

```bash
devenv tasks run build:darwin
```

### NixOS Only

```bash
devenv tasks run build:nixos
```

## Fixing Issues

### Formatting Problems

```bash
# See what needs formatting
devenv tasks run check:lint

# Auto-fix formatting
devenv tasks run format:all
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

After applying the configuration, these shortcuts are available:

```bash
q       # devenv tasks run check:all
b       # devenv tasks run build:all
```

> **See also:** [Tasks Reference](../reference/tasks.md) for the full task list
