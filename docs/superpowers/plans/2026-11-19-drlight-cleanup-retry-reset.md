# Drlight Cleanup Retry Reset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe, manual operation to make all valid queued cleanup receipts due, then allow the normal cleanup service to evaluate them immediately.

**Architecture:** Add an atomic retry-deadline reset helper to the module that owns staged-torrent receipts. Expose it through a CLI mode and a manually started, network-isolated NixOS oneshot service; cleanup continues through the existing service and safeguards.

**Tech Stack:** Python 3, unittest, NixOS systemd modules, devenv/Nix checks.

**Spec:** `docs/superpowers/specs/2026-11-19-drlight-cleanup-retry-reset.md`

## Global Constraints

- Modify Nix configuration and its tests only; do not change the deployed machine directly.
- Reset only valid queue entries and preserve attempt counts, receipt IDs, fingerprints, and other receipt data.
- Use `staged_at_ns` as the new `next_attempt_ns`; negative or earlier-than-staged values are invalid.
- Serialize receipt updates with the existing queue lock and write them atomically.
- The reset must not bypass any cleanup eligibility, ownership, import-proof, file-match, or final revalidation gate.
- Keep the reset service manual-only; do not add a timer or network access.

## Review Focus

- Malformed, symlinked, or replaced receipt files must be skipped rather than rewritten; test malformed and symlinked entries in the reset helper test.
- Retry history must survive a reset; assert `attempts`, receipt ID, and fingerprint are unchanged.
- The normal cleanup service must remain the only service that can perform deletion; assert reset service invokes reset mode only and has no network access.
- Cleanup-disabled configurations must not expose the reset service; assert its absence in the existing archetype test.
- Resetting deadlines must make valid future receipts immediately due under the current queue reader; assert with a fixed `now_ns` earlier than the receipt's original retry time.

---

### Task 1: Add a safe manual retry-deadline reset

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Modify: `modules/nixos/ultra-media-cleanup.nix`
- Test: `tests/test-ultra-media-cleanup.py`
- Test: `tests/test-media-center-archetype.nix`

**Interfaces:**
- Produce `reset_staged_torrent_receipt_retry_times(queue_root: str | Path) -> int` in the staging queue module; it returns the count updated.
- Add mutually exclusive CLI mode `--reset-retry-times`; it prints a privacy-safe JSON result and does not read runtime secrets or invoke cleanup.
- Add manual-only `ultra-media-cleanup-reset-retries.service`, running as `ultra-sync`, with access only to the persistent state directory and no network.

- [x] **Step 1: Write failing receipt-reset tests**

Add tests proving that valid future-due receipts become readable as due at their staged timestamp, and that attempt counts, receipt IDs, and fingerprints are preserved. Add a malformed/symlinked receipt case proving those entries are not modified or counted.

- [x] **Step 2: Run the focused tests and confirm the expected failure**

Run: `python3 tests/test-ultra-media-cleanup.py modules/nixos/scripts/ultra-media-cleanup.py modules/nixos/scripts/transmission_rpc.py modules/nixos/scripts/ultra-media-download-stage.py modules/nixos/scripts DownloadStagingTests`
Expected: the new reset-helper tests fail because the helper does not exist.

- [x] **Step 3: Implement the receipt reset helper**

In `ultra-media-download-stage.py`, validate the existing receipt schema, acquire `cleanup_queue_lock`, set `next_attempt_ns` to each valid receipt's `staged_at_ns`, and use `_write_receipt_atomic`. Preserve all other receipt fields.

- [x] **Step 4: Run the receipt-reset tests**

Run: `python3 tests/test-ultra-media-cleanup.py modules/nixos/scripts/ultra-media-cleanup.py modules/nixos/scripts/transmission_rpc.py modules/nixos/scripts/ultra-media-download-stage.py modules/nixos/scripts DownloadStagingTests`
Expected: all download-staging and receipt queue tests pass.

- [x] **Step 5: Add failing CLI and Nix service tests**

Assert that `--reset-retry-times` invokes only the reset operation, rejects incompatible `--apply` / `--report-only` combinations, and emits the updated count. In the archetype test, assert the manual reset service exists only when cleanup is enabled, uses the `ultra-sync` account and StateDirectory, runs reset mode, and is network-isolated.

- [x] **Step 6: Run the focused checks and confirm the expected failure**

Run: `python3 tests/test-ultra-media-cleanup.py modules/nixos/scripts/ultra-media-cleanup.py modules/nixos/scripts/transmission_rpc.py modules/nixos/scripts/ultra-media-download-stage.py modules/nixos/scripts` and `nix build .#checks.x86_64-linux.drlight-media-storage --impure --no-link`
Expected: new CLI and service assertions fail before implementation.

- [x] **Step 7: Implement CLI and NixOS service wiring**

Add `--reset-retry-times` as a standalone CLI mode in `ultra-media-cleanup.py`; reject conflicting modes. Define the manual-only reset service in `ultra-media-cleanup.nix` with `User=ultra-sync`, `Group=users`, `StateDirectory=ultra-media`, strict filesystem protection, no network, and command arguments limited to `--reset-retry-times --queue-root ...`.

- [x] **Step 8: Run focused tests and checks**

Run: `python3 tests/test-ultra-media-cleanup.py modules/nixos/scripts/ultra-media-cleanup.py modules/nixos/scripts/transmission_rpc.py modules/nixos/scripts/ultra-media-download-stage.py modules/nixos/scripts` and `nix build .#checks.x86_64-linux.drlight-media-storage --impure --no-link`
Expected: all Python tests and Drlight media-management assertions pass.

- [x] **Step 9: Run repository lint and full tests**

Run: `devenv tasks run check:lint` and `devenv tasks run test:all`
Expected: both commands exit successfully.
