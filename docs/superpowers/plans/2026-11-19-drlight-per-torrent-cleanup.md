# Drlight Per-Torrent Cleanup and Completion-Age Retention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate cleanup ownership failures by download-directory scope and use Transmission `doneDate` for the 240-hour retention threshold.

**Architecture:** Replace the global inventory-valid flag with an unknown-scope flag plus normalized incomplete download-directory scopes. Compute exact source-path owner counts from valid inventory records and verify each candidate against those counts and scopes. Carry validated `doneDate` into cleanup candidates and qualify by completion age or the existing torrent-ratio threshold.

**Tech Stack:** Python, unittest, Nix checks.

**Spec:** `docs/superpowers/specs/2026-11-19-drlight-per-torrent-cleanup.md`

## Global Constraints

- Unknown ownership never authorizes deletion.
- An invalid/unknown download directory remains a global ownership blocker.
- Completion-age retention is 240 hours since `doneDate`, or upload/download ratio at least 3.0; invalid `doneDate` fails closed unless the ratio independently qualifies.
- Keep import proof, local-file revalidation, per-torrent queue processing, and redacted aggregate reporting unchanged.

## Review Focus

- A malformed record in a separate download directory must not block a valid candidate.
- A malformed record in the candidate's download directory must block that candidate.
- An unbounded invalid directory or empty inventory must continue to block cleanup.
- Duplicate exact source paths must remain blocked as shared ownership.
- Recent completion with low ratio stays blocked; an old completion qualifies even when `secondsSeeding` is zero; missing/invalid completion time is unknown.

---

### Task 1: Scope ownership uncertainty to download directories

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Test: `tests/test-ultra-media-cleanup.py`

**Interface:** `build_cleanup_candidates(torrents, mappings, imported_paths, *, staging_root, path_mapper)` continues returning normalized candidate dictionaries. File records continue using `source_ownership_verified` and `source_owner_count`.

- [ ] Add a test with one valid candidate under `/seedbox/complete` and one malformed inventory record under `/seedbox/other`; assert the valid candidate has verified unique ownership and remains eligible for cleanup.
- [ ] Run the focused cleanup test and confirm the new test fails because the existing global inventory flag marks ownership unknown.
- [ ] Add an incomplete-directory scope set and a global-unknown flag; count valid exact source paths, and mark ownership unknown only for candidates under an incomplete scope, or globally when the invalid record has no safe scope.
- [ ] Preserve shared-path checks and current same-directory incomplete-inventory behavior.
- [ ] Run `nix build .#checks.x86_64-linux.drlight-ultra-media-cleanup --no-link` and confirm all cleanup tests pass.

### Task 2: Use Transmission completion time for retention

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Test: `tests/test-ultra-media-cleanup.py`

**Interface:** `evaluate_retention(candidate, *, now_seconds=None)` reads a positive integer `candidate["done_date"]`; candidates receive this value from the normalized Transmission torrent record.

- [ ] Add RED tests for 240-hour completion age with zero seeding seconds, recent completion below 240 hours with ratio below 3.0, ratio-based eligibility, and missing `doneDate`.
- [ ] Run the focused cleanup check and confirm these tests fail against seeding-time retention.
- [ ] Carry `done_date` into each cleanup candidate and replace the seeding-time check with completion-age calculation; keep ratio and other safety gates intact.
- [ ] Add/adjust fixtures to provide completion timestamps and run the focused cleanup check.

### Task 3: Validate and review

- [ ] Run `devenv tasks run check:lint`.
- [ ] Run the focused Nix cleanup check again after formatting.
- [ ] Inspect the final diff for any weakened cleanup gate or identifier/path leakage.
