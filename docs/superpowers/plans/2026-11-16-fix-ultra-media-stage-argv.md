# Fix Ultra Media Staging Arguments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the Drlight systemd staging and cleanup services pass their required command-line options to their scripts.

**Architecture:** Keep the existing shell-script services and argument lists. Correct shell continuations in both Nix indented strings and add regression assertions against the evaluated service commands, which NixOS renders into the unit wrappers.

**Tech Stack:** NixOS systemd module, Nix evaluation checks, Jujutsu.

**Spec:** `docs/plans/2026-11-09-ultra-media-retention.md`

## Global Constraints

- Cleanup remains gated on a successful staging service.
- Do not deploy or activate Drlight as part of this fix.
- Follow the repository's Jujutsu and Nix validation workflow.

## Review Focus

- Shell line continuation escaping: assert both evaluated commands contain single-backslash/newline continuations and no doubled-backslash/newline sequence.
- Required argument preservation: keep both services' existing flags and paths unchanged.
- Cleanup trigger: preserve `OnSuccess` semantics; a failed stage must not start cleanup.

---

### Task 1: Fix staging command continuation and guard it with a regression test

**Ruling:** The staging command assertions live in the `drlight-media-storage` check, not `media-center-archetype`; use the former as the focused check.

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `modules/nixos/ultra-media-cleanup.nix`
- Test: `tests/test-media-center-archetype.nix`

- [x] Add assertions that both evaluated commands contain a single backslash followed by a newline and do not contain two backslashes followed by a newline.
- [x] Run `nix build .#checks.x86_64-linux.drlight-media-storage --no-link --impure` and confirm the new assertions fail on the doubled-backslash commands.
- [x] Replace doubled shell-continuation backslashes in both Nix indented scripts with single backslashes, preserving every existing CLI flag and argument.
- [x] Re-run `nix build .#checks.x86_64-linux.drlight-media-storage --no-link --impure` and confirm it passes.
- [x] Run `devenv tasks run check:lint`; after committing, run `devenv tasks run test:build-checks`.
- [ ] Commit with `jj describe -m "fix: pass staging arguments to the systemd job"` and push the PR bookmark using Jujutsu.
- [ ] Check PR 567's updated status; do not deploy or activate the host.
