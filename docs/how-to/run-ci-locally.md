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

### CI Check Suites

To run the flake check suites used by PR CI:

```bash
# Non-VM checks only
devenv tasks run ci:checks:non-vm

# NixOS VM checks only (requires x86_64-linux and KVM)
devenv tasks run ci:checks:vm

# Both suites in parallel
devenv tasks run ci:checks
```

The VM suite caps Nix builds at two concurrent jobs. Run a leaf task when you
want to avoid starting the other suite.

## Platform-Specific Validation

### Configuration Evaluation

```bash
devenv tasks run test:eval
```

Evaluates all NixOS and Darwin configurations without building. This is the fastest way to catch option errors and missing references.

## Machine Command Safety Checks

The machine-operation wrapper can be tested without contacting a target or
loading 1Password credentials:

```bash
bash tests/test-machine-ops.sh
```

It uses mock `devenv`, `secretspec`, and catalog lookup commands to verify that
machine names are explicit, profiles are operation-scoped, deployment never
adds `--yes`, and installation cancels unless disk erasure is affirmatively
confirmed. The focused Nix check also exercises the pinned SecretSpec CLI with
temporary HOME and a failing `op` stub against the empty Homelab and Personal
profiles, without accessing 1Password. The Nix check is available as:

```bash
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machines-ops" --no-link
```

For task invocation, use an explicit JSON task input, for example:

```bash
devenv tasks run machines:build --input machine=zero
devenv tasks run machines:check --input machine=zero
devenv tasks run machines:plan --input machine=zero
```

`machines:info` is the only operation that intentionally lists the full
inventory. Remote operation smoke tests must use disposable VMs; do not run
`deploy` or `install` against production machines as part of local CI checks.
See the [Tasks Reference](../reference/tasks.md#named-machine-operations) for
local endpoint overrides and SecretSpec profile behavior.

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
