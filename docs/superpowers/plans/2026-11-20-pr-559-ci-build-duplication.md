# PR 559 CI Build Duplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Avoid building the same Devenv derivation in both the foundation-package and machine SecretSpec checks.

**Architecture:** Keep `pkgs.devenv` in the configured foundation package set and retain the existing Devenv membership assertion. Remove it only from the foundation package test's build inputs and command spot-check; the machine SecretSpec check continues exercising the pinned Devenv executable.

**Tech Stack:** Nix, Nix flake checks, Jujutsu.

**Spec:** `docs/superpowers/specs/2026-11-20-pr-559-ci-build-duplication-design.md`

## Global Constraints

- Do not change the configured foundation package set.
- Keep the Devenv package inclusion assertion and actual SecretSpec runtime coverage.
- Do not change CI timeouts or PR 559's flake input/lockfile cleanup.

## Review Focus

- The Devenv CLI remains installed in the configured foundation role: assert the package remains in `foundation-packages.nix`.
- The foundation package availability test no longer pulls in the Devenv derivation: assert Devenv is absent from that test's `nativeBuildInputs`.
- Runtime behavior remains covered by the machine SecretSpec test: retain its existing invocation of the pinned Devenv `secretspec` executable.

---

### Task 1: Remove the duplicate Devenv build from foundation package checks

**Files:**
- Modify: `tests/test-devenv-packages.nix`
- Modify: `tests/test-packages.nix`
- Test: `tests/test-devenv-packages.nix`

**Interfaces:**
- Consumes: `foundationPackagesTest` from `tests/test-packages.nix` and the configured packages from `modules/roles/foundation-packages.nix`.
- Produces: a regression assertion that Devenv remains configured but is not a build input of `foundationPackagesTest`.

- [ ] **Step 1: Add the failing regression assertion**

In `tests/test-devenv-packages.nix`, import `modules/roles/foundation-packages.nix` and `tests/test-packages.nix`. Assert that `pkgs.devenv` remains in the configured foundation package list and is absent from `foundationPackagesTest.nativeBuildInputs`.

- [ ] **Step 2: Run the focused check and confirm it fails**

Run: `nix build --impure path:.#checks.aarch64-darwin.devenv-packages --no-link`

Expected: failure because the current foundation package test includes `pkgs.devenv` in `nativeBuildInputs`.

- [ ] **Step 3: Remove the duplicate build dependency**

In `tests/test-packages.nix`, remove `devenv` from `foundationPackagesTest.nativeBuildInputs` and from its command availability loop. Leave `modules/roles/foundation-packages.nix`, the Devenv membership assertion, and `tests/test-machine-ops.nix` unchanged.

- [ ] **Step 4: Run focused and repository checks**

First describe the working copy with `jj describe -m "fix: avoid duplicate Devenv CI build"` so the repository's commit-first requirement is met. Then run: `nix build path:.#checks.aarch64-darwin.devenv-packages path:.#checks.aarch64-darwin.foundation-packages --no-link`

Expected: both focused checks succeed. Also run `devenv tasks run check:lint` and `devenv tasks run test:build-checks` against the described workspace tree.

- [ ] **Step 5: Describe the change and finish the workspace**

Run `jj new` after all validation succeeds to leave an empty working copy.
