---
name: nix
description: Nix development skill for working with flakes, modules, and configurations
---

Use this skill when working with Nix flakes, modules, or configurations.

## Conventions
- Use `mkOption` for all configurable values
- Place modules in appropriate directories: common/, nixos/, darwin/
- Test with `devenv tasks run check:lint` before finishing
- Follow existing patterns in the codebase

## Tools
- Read existing modules in modules/ for examples
- Use lib.optionalAttrs for platform-specific config
- Check modules/roles/ for role definitions
