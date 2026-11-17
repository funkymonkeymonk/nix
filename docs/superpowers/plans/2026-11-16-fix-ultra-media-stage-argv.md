# Fix Ultra Media Staging Arguments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the Drlight systemd staging and cleanup services pass their required command-line options and can create temporary files under their systemd sandbox.

**Architecture:** Keep the existing shell-script services and argument lists. Correct shell continuations in both Nix indented strings and add regression assertions against the evaluated service commands. Set `TMPDIR` to the private `/run/ultra-media` directory already allowed by each unit's filesystem sandbox.

**Tech Stack:** NixOS systemd module, Nix evaluation checks, Jujutsu.

**Spec:** `docs/plans/2026-11-09-ultra-media-retention.md`

## Global Constraints

- Cleanup is gated per torrent by a receipt written only after that torrent's files are fully published.
- Deploy Drlight only through the reviewed Machines plan/apply workflow.
- Let the one-minute cleanup timer consume per-torrent receipts; preserve report-mode policy gates.
- Follow the repository's Jujutsu and Nix validation workflow.

## Review Focus

- Shell line continuation escaping: assert both evaluated commands contain single-backslash/newline continuations and no doubled-backslash/newline sequence.
- Required argument preservation: keep both services' existing flags and paths unchanged.
- Cleanup queue: never enqueue partial or failed torrents; a failure in one torrent does not revoke already completed receipts for other torrents.
- Systemd filesystem sandbox: direct Python temporary files to `/run/ultra-media`, not the read-only default temp directory.

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
- [x] Commit with `jj describe -m "fix: pass arguments to media systemd jobs"` and push the PR bookmark using Jujutsu.
- [x] Check PR 567's updated status (CI was pending at that time).

### Task 2: Put Python temporary files in the writable runtime directory

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `modules/nixos/ultra-media-cleanup.nix`
- Test: `tests/test-media-center-archetype.nix`

- [x] Add assertions that both services set `environment.TMPDIR` to `/run/ultra-media`.
- [x] Run `nix build .#checks.x86_64-linux.drlight-media-storage --no-link --impure` and confirm both assertions fail before implementation.
- [x] Set `TMPDIR` to `/run/ultra-media` for both systemd services; confirm the focused check passes.
- [x] Run `devenv tasks run check:lint` and `devenv tasks run test:all`; commit the change.
- [ ] Push the PR update using Jujutsu.
- [x] Apply reviewed Drlight Machines plans for the job argument and writable-temp fixes; staging now runs with the corrected arguments and runtime temp directory.
