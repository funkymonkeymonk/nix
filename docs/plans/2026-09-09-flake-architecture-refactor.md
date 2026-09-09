# Flake Architecture Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Finish the migration to a consistent, pure, flake-parts-based architecture through independently reviewable stacked PRs.

**Architecture:** Keep reusable modules and archetypes separate from machine declarations. Define machine outputs in flake-parts modules, expose platform-specific outputs only on supported systems, and derive CI configuration lists from flake outputs rather than duplicating names.

**Tech Stack:** Nix flakes, flake-parts, NixOS, nix-darwin, devenv tasks, Jujutsu, GitHub CLI.

### Task 1: Restore Linux evaluation

- Gate Darwin-only MLX packages in `flake.nix` or expose them only from the Darwin `perSystem` scope.
- Add or update a package-output regression check.
- Verify `devenv tasks run test:build-checks` on Linux.
- Commit and open a PR on top of PR 453.

### Task 2: Extract bootstrap and installer machine declarations

- Create flake-parts machine modules for `bootstrap` and `installer-iso`.
- Move ISO contents and bootstrap-only inline settings into target modules.
- Import the machine modules from `flake.nix` and remove their direct declarations.
- Verify target evaluation and ISO-related checks.
- Commit and open a PR stacked on Task 1.

### Task 3: Extract cattle machine declarations

- Create a flake-parts machine module for `type-nas`, `type-server`, `type-server-arm`, and `type-desktop`.
- Preserve builder arguments, overrides, disk modules, and target modules exactly.
- Remove their declarations from `flake.nix`.
- Verify all cattle configuration and observability checks.
- Commit and open a stacked PR.

### Task 4: Convert outputs to `perSystem`

- Move package and app generation to flake-parts `perSystem` modules.
- Move checks to platform-specific `perSystem` definitions while retaining existing test names.
- Use platform conditions for unsupported packages and checks.
- Verify flake evaluation, linting, and build checks.
- Commit and open a stacked PR.

### Task 5: Remove duplicate library plumbing

- Use the `libraryLib` and `mkUser` arguments exported by `library/flake-module.nix`.
- Remove the direct `mk-system.nix` import from the root flake.
- Add a regression assertion that machine modules receive the shared arguments.
- Commit and open a stacked PR.

### Task 6: Normalize configuration boundaries

- Document and enforce the division between archetypes, machine declarations, host/target settings, and reusable modules.
- Move any remaining machine-specific settings from `machine-types/` into the appropriate target or host modules.
- Avoid behavior changes and preserve existing output names.
- Add structural tests for the normalized layout.
- Commit and open a stacked PR.

### Task 7: Make hardware inputs explicit

- Replace implicit `/etc/nixos/facter.json` discovery in reusable evaluation paths with an explicit hardware module argument or target import.
- Keep deployment-time hardware discovery available through a dedicated impure entry point.
- Update stubs and evaluation tests to use explicit inputs.
- Verify pure flake evaluation for all configurations.
- Commit and open a stacked PR.

### Task 8: Derive CI target lists

- Replace hardcoded configuration lists in CI validation with `nix eval` over flake output attributes.
- Preserve exclusions for unsupported platforms and special outputs.
- Add a test that detects newly added configurations without manual CI edits.
- Commit and open a stacked PR.

Each task is implemented and verified before the next dependent bookmark is created. Every PR targets the preceding PR branch, with the final PR targeting the complete stack.
