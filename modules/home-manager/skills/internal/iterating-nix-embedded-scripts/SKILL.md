---
name: iterating-nix-embedded-scripts
description: Use when iterating on shell scripts embedded in Nix modules via writeShellScriptBin, writeShellApplication, writeScriptBin, or writeText — avoids slow build/switch cycles for every edit
---

# Iterating on Nix-embedded shell scripts

## Overview

Shell scripts defined inside Nix derivations (`pkgs.writeShellScriptBin` et al.) normally force a full `darwin-rebuild switch` / `nixos-rebuild switch` per change — 30s to 5 min per iteration.

**Core principle:** Use `nix build` to materialize the script into `/nix/store` with all interpolations resolved, and run it from there. Edit the Nix source directly, rebuild, run. Never hand-extract — Nix escaping (`''${`, `''$`, `'''`) and `${pkgs.xxx}` interpolation are easy to get wrong.

## When to Use

- Editing a `writeShellScriptBin`, `writeShellApplication`, `writeScriptBin`, `writeScript`, or `writeText`-backed script inside a flake
- About to run `darwin-rebuild switch` / `nixos-rebuild switch` just to test a one-line shell change
- About to hand-copy a script body to `/tmp` to iterate on it
- Unsure whether the bug is in shell logic or in Nix interpolations

**Do not use for:** Nix expressions that aren't producing runnable scripts (modules, options, services). Those need eval tests or `nix flake check`, not script execution.

## Workflow

1. **Find the derivation.** Usually in `config.environment.systemPackages` (NixOS/Darwin system module) or `config.home.packages` (home-manager). If defined in a `let` binding, filter the list by `pname` / `name`.

2. **Build with an out-link:**
   ```bash
   nix build --impure --out-link /tmp/<name>-result --expr '
     let
       flake = builtins.getFlake (toString /ABS/PATH/TO/FLAKE);
       syspkgs = flake.darwinConfigurations.<host>.config.environment.systemPackages;
     in builtins.head (builtins.filter
       (p: (p.pname or p.name or "") == "<script-name>") syspkgs)
   '
   ```
   `/tmp/<name>-result/bin/<script-name>` is runnable and fully interpolated.

3. **Iterate:** edit the `.nix` file → rerun the `nix build` → execute the result. ~10–15s per cycle (mostly flake eval; the build step itself is ~1–2s).

4. **You're already "reimported."** You were editing the Nix source the whole time. Nothing to sync back. When happy, run your normal `switch` once.

## Helper

Bundled `nix-script-iter` wraps the filter-and-build pattern:

```bash
nix-script-iter <flake-path> <config-name> <script-pname> [-- <script-args>]
```

Run `nix-script-iter` with no args for usage.

## Common Pitfalls

**Don't hand-extract the script body.** Manual transcription drops `${pkgs.xxx}` interpolations and mangles escape sequences. Always let `nix build` produce the runnable script.

**Nonexistent nixpkgs paths fail fast with `nix build`.** Example: `${pkgs.darwin.system_profiler}` looks plausible but doesn't exist (`system_profiler` is a macOS system binary at `/usr/sbin/system_profiler`). `nix build` errors in ~2s; `darwin-rebuild switch` would take much longer to reveal the same bug.

**Use `--impure`.** Flake eval reads from git HEAD without it. `--impure` lets it read the working tree so you don't have to commit every iteration.

**Multiple derivations with the same `pname`.** Tighten the filter — include `version`, or traverse a precise attribute path instead of scanning `systemPackages`.

## Real-World Impact

Aerospace summon script (~60 lines): `darwin-rebuild switch` is 2–5 min; this loop is ~13s per cycle. Catches mistakes like `pkgs.darwin.system_profiler` (nonexistent attr) in 2s.
