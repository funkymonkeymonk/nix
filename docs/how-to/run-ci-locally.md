# Run CI Locally

This guide shows you how to run CI validation on your local machine.

## Quick Validation (~30 seconds)

For fast feedback during development:

```bash
devenv tasks run ci:quick
```

This runs:
- Flake syntax check
- Code formatting (alejandra)
- Dead code detection (deadnix)
- Static analysis (statix)

## Full PR Validation

Before opening a PR:

```bash
devenv tasks run ci:pr
```

This includes everything from `ci:quick` plus:
- Darwin configuration validation
- NixOS configuration validation

## Platform-Specific Validation

### Darwin Only

```bash
devenv tasks run ci:validate:darwin
```

### NixOS Only

```bash
devenv tasks run ci:validate:nixos
```

## Fixing Issues

### Formatting Problems

```bash
# See what needs formatting
devenv tasks run ci:lint

# Auto-fix formatting
devenv tasks run ci:format
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

The CI validates both platforms regardless of your host:

| Host Platform | What Gets Validated |
|---------------|---------------------|
| macOS | Darwin configs (full) + NixOS configs (eval only) |
| Linux | NixOS configs (full) + Darwin configs (eval only) |

## Shell Aliases

After applying the configuration, these shortcuts are available:

```bash
q       # devenv tasks run quality:check
t       # devenv tasks run test:run
tf      # devenv tasks run test:full
```

> **See also:** [CI/CD Reference](../reference/ci.md) for the full pipeline details
