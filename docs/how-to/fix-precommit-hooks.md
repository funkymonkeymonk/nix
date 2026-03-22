# Fixing Pre-Commit Hook Failures

This guide helps you fix pre-commit hook failures instead of bypassing them.

## Available Hooks

| Hook | Runs On | Purpose | Time |
|------|---------|---------|------|
| alejandra | pre-commit | Nix formatting | ~1s |
| statix | pre-commit | Static analysis | ~1s |
| deadnix | pre-commit | Dead code detection | ~1s |
| yamllint | pre-commit | YAML validation | ~1s |
| quick-nix-check | pre-commit | Nix syntax check | <1s |
| flake-check | pre-push | Full flake evaluation | ~20s |
| docs-update | pre-push | Auto-update docs | ~2s |

## Common Failures and Fixes

### alejandra (Formatting)

**Error:** `Formatting error in file.nix`

**Fix:**
```bash
# Auto-format all files
devenv tasks run format:all

# Or format specific file
alejandra path/to/file.nix
```

### statix (Static Analysis)

**Error:** Various anti-pattern warnings

**Fix:**
```bash
# See detailed output
statix check .

# Common fixes:
# - Use `==` instead of `=` for equality
# - Remove unnecessary parentheses
# - Use `with pkgs;` consistently
```

### deadnix (Dead Code)

**Error:** `Unused variable 'foo' at file.nix:42:5`

**Fix:**
```nix
# Before (warning)
{ pkgs, lib, ... }: { }

# After (if lib is unused)
{ pkgs, _lib, ... }: { }

# Or remove the parameter if truly unused
{ pkgs, ... }: { }
```

### quick-nix-check (Syntax)

**Error:** `syntax error, unexpected '}'`

**Fix:**
```bash
# Check specific file
nix-instantiate --parse file.nix

# Common issues:
# - Missing semicolon after attribute
# - Mismatched brackets/parentheses
# - Invalid escape sequences in strings
```

### flake-check (Evaluation)

**Error:** `error: The option 'programs.foo.enable' does not exist`

**Fix:**
```bash
# Get full error details
nix flake check --no-build --all-systems --show-trace

# Common fixes:
# - Check option exists in nixpkgs (search NixOS options)
# - Remove invalid option
# - Use correct module context (NixOS vs home-manager)
```

## Bypassing Hooks (Last Resort)

**Only bypass if:**
- You're in an emergency situation
- You've documented why in the commit message
- You plan to fix it immediately after

```bash
# Bypass pre-commit hooks
 git commit -m "WIP: temporary commit" --no-verify

# Bypass pre-push hooks
git push --no-verify
```

**⚠️ Warning:** Bypassing hooks means CI will likely fail. Fix the issues before opening a PR.

## Testing Hooks Locally

```bash
# Run all pre-commit hooks manually
pre-commit run --all-files

# Run specific hook
pre-commit run alejandra --all-files

# Run pre-push hooks manually
pre-commit run --hook-stage pre-push
```

## Agent Guidelines

When fixing hook failures:

1. **Never bypass without documenting why** - Add a comment explaining the bypass
2. **Fix the root cause** - Don't just silence the warning
3. **Test locally** - Run the hook manually to verify the fix
4. **Keep fixes minimal** - Don't reformat entire files, just fix the issue
5. **Ask for help** - If stuck on a complex error, ask before bypassing

## Common Patterns

### Fixing Option Errors

```nix
# ERROR: option 'programs.fzf.enable' does not exist
# FIX: Check if it's a NixOS or home-manager option

# Wrong (in NixOS system config)
programs.fzf.enable = true;

# Right (in home-manager config)
programs.fzf = {
  enable = true;
  enableZshIntegration = true;
};
```

### Fixing Module Scope

```nix
# ERROR: attribute 'myConfig' missing
# FIX: Pass via _module.args in parent module

# In parent module (users.nix):
_module.args = {
  userConfig = user;
  inherit (config) myConfig;
};

# In child module (foundation.nix):
{ config, lib, userConfig, myConfig, ... }: {
  # Now myConfig is available
}
```

### Fixing Sandbox Issues in Tests

```nix
# ERROR: Cannot build - requires <nixpkgs> which is forbidden in pure mode
# FIX: Use passed pkgs instead of importing nixpkgs

# Wrong (in test)
nix-instantiate --eval --expr "(import <nixpkgs> {}).git"

# Right (in test)
# Reference packages from the passed pkgs set instead
```

## See Also

- [Run CI Locally](./run-ci-locally.md) - Full local validation
- [Tasks Reference](../reference/tasks.md) - Available devenv tasks
- [Architecture](../explanation/architecture.md) - Understanding the codebase structure
