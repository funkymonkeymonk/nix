# Aggressive Seedbox Cleanup Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make Drlight's seedbox cleanup policy declaratively configurable and set it to 24 hours or a 1.0 torrent ratio.

**Architecture:** Add cleanup threshold options to the NixOS staging module. Pass them as validated CLI values through the unified sync worker into the cleanup runtime, where the existing retention evaluator uses them. Preserve all staging, ownership, local verification, tracker, and final revalidation gates.

**Tech Stack:** Nix, Python, NixOS systemd, existing Python/Nix checks.

**Spec:** `docs/superpowers/specs/2026-11-25-aggressive-seedbox-cleanup-design.md`

## Global Constraints

- Cleanup remains limited to fully staged, receipt-backed torrents.
- Retain all existing path, ownership, size/mtime, tracker, and fresh revalidation safeguards.
- Drlight uses 24 completion hours or a 1.0 torrent ratio.
- Do not deploy or invoke live torrent removal.

## Review Focus

- Thresholds must be passed consistently from Nix to the unified worker and cleanup runtime; test generated arguments and runtime propagation.
- Invalid/non-positive thresholds must fail closed rather than silently broadening deletion; test CLI validation.
- Existing default behavior must remain unchanged for callers that do not provide overrides; test Python defaults.
- Ratio-or-age semantics must remain disjunctive; test each threshold independently and below both.
- The private-tracker protection switch must remain independent of the new thresholds; retain existing machine configuration coverage.

---

### Task 1: Make retention thresholds injectable

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Test: `tests/test-ultra-media-cleanup.py`

**Interfaces:**
- `evaluate_retention(candidate, *, now_seconds=None, min_completion_age_seconds=240 * 60 * 60, min_torrent_ratio=3.0)` continues to default to the current policy while accepting validated overrides.
- `run_runtime_cleanup(..., min_completion_age_seconds=..., min_torrent_ratio=...)` forwards the values to candidate evaluation.

- [ ] Add failing tests proving 24-hour and 1.0-ratio overrides qualify candidates, while candidates below both remain blocked.
- [ ] Add failing tests for invalid/non-positive threshold values.
- [ ] Implement validation and pass the configured values through cleanup evaluation without changing any other gate.
- [ ] Run the focused Python cleanup test suite and confirm it passes.

### Task 2: Wire options through the unified worker and NixOS module

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `modules/nixos/scripts/ultra-media-sync.py`
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Modify: `machines/drlight/default.nix`
- Test: `tests/test-media-center-archetype.nix`

**Interfaces:**
- Nix options under `myConfig.ultraMediaDownloadStage.cleanup`: `minCompletionAgeHours` and `minTorrentRatio`.
- Unified worker CLI flags: `--min-completion-age-hours` and `--min-torrent-ratio`.
- Cleanup runtime receives seconds and ratio explicitly.

- [ ] Add Nix assertions that Drlight exposes and passes 24 hours / 1.0.
- [ ] Add CLI parsing and validation for both worker flags, retaining current defaults.
- [ ] Pass the values from the systemd service command into `ultra-media-sync.py`, then into cleanup.
- [ ] Run the focused Nix media-center and Python cleanup checks.

### Task 3: Validate and summarize

- [ ] Run `devenv tasks run check:lint`.
- [ ] Review the diff for accidental changes and confirm no deployment/removal command was run.
- [ ] Describe the changes with a conventional Jujutsu message and create a fresh empty commit.
