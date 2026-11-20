# Drlight Unified Sync and Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one scheduled Drlight worker sync completed torrents to staging, then remove seedbox torrents/data that are synced and retention-eligible, with useful structured telemetry.

**Architecture:** Add a small Python orchestrator that runs the existing per-torrent staging operation before the cleanup operation. Replace Arr history/library proof with a final source-to-staged-copy verification; retain retention, source ownership, receipt matching, locks, and revalidation. Provision one systemd worker/timer and point the existing Grafana dashboard at its JSON events.

**Tech Stack:** Python 3, unittest, NixOS systemd modules, Nix evaluation tests, Grafana/Loki, Prometheus textfile metrics.

**Spec:** `docs/superpowers/specs/2026-11-19-drlight-unified-sync-cleanup.md`

## Global Constraints

- Keep the existing hourly schedule and one systemd worker.
- A receipt is created only after every file for that torrent has been completely published to Drlight staging.
- Cleanup may remove a torrent and its seedbox data only when its staged copy is verified, its retention rule qualifies, source mapping and unique ownership are proven, and final live-state revalidation succeeds.
- Preserve the existing retention rule: completion age is at least 240 hours since Transmission `doneDate`, or torrent ratio is at least 3.0.
- Arr import state is independent and is not a seedbox-cleanup prerequisite.
- Preserve fail-closed handling for unknown paths, shared ownership, invalid inventory scope, changed fingerprints, missing or mismatched staged files, and failed revalidation.
- Emit aggregate JSON only; do not log torrent IDs, names, source/library paths, endpoints, or secrets.

## Review Focus

- A failed/partial torrent transfer must not create a receipt or authorize its deletion; add a test that checks the receipt callback runs only after every file is published.
- A staged copy with missing, wrong-size, wrong-mtime, symlinked, or out-of-root files must remain blocked; add focused staged-proof tests.
- One failed torrent must not prevent cleanup of another successfully staged torrent; add an orchestration test with a partial stage result and independent cleanup result.
- Changed source ownership, duplicate paths, stale fingerprints, or failed final revalidation must remain non-deletable; retain and update existing safety tests.
- Grafana queries must use the single worker service label and show JSON transfer, cleanup, and run-summary events without identifying paths or torrents; assert the provisioned dashboard expressions and fields.

---

### Task 1: Make verified Drlight staging the cleanup proof

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Test: `tests/test-ultra-media-cleanup.py`

**Interfaces:**
- Replace Arr-dependent candidate construction with `build_cleanup_candidates(torrents, mappings, *, staging_root, path_mapper)`; each file record retains `remote_path`, `staged_path`, expected source size, and ownership evidence, but no Arr `local_path`.
- Replace the Arr adapter with `make_staged_copy_prover(source_stat, *, staging_root=None)`, which verifies every file is a regular file under staging, with size and nanosecond mtime matching the live remote source.
- `run_runtime_cleanup` no longer takes an Arr config path, reads Arr API keys/history, or requires library roots.

- [x] **Step 1: Write failing staged-copy tests**
  - Test that a fully staged candidate with exact source/staged size and mtime passes the proof and that cleanup does not call any Arr API.
  - Test that missing files, size or mtime mismatch, symlinked files, and paths outside the staging root fail closed.
  - Test that retention and ownership checks still block candidates before any destructive Transmission call.
- [x] **Step 2: Run focused tests and verify RED**
  - Run `python3 tests/test-ultra-media-cleanup.py modules/nixos/scripts/ultra-media-cleanup.py modules/nixos/scripts/transmission_rpc.py modules/nixos/scripts/ultra-media-download-stage.py modules/nixos/scripts CleanupRuntimeTests`.
  - Expected: tests fail because candidates/proofs still depend on Arr import mappings.
- [x] **Step 3: Implement the staged-copy proof**
  - Remove Arr history fetching, Arr config parsing, imported-path mapping, and local-library file verification from the cleanup path.
  - Build each cleanup candidate directly from Transmission metadata and its exact stage destination.
  - Preserve unique source ownership, source/stage equality, receipt matching, retention, locking, and revalidation.
- [x] **Step 4: Run focused tests and verify GREEN**
  - Run the focused cleanup runtime/execution tests and the full Python test file.
  - Expected: all staged-copy tests and unaffected retention, ownership, receipt, and RPC tests pass.

### Task 2: Add one ordered sync-and-cleanup runner with JSON summaries

**Files:**
- Create: `modules/nixos/scripts/ultra-media-sync.py`
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py` (return aggregate transfer counters)
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py` (expose runtime call without Arr arguments)
- Test: `tests/test-ultra-media-cleanup.py`

**Interfaces:**
- Add `run_sync_cycle(stage_runner, cleanup_runner) -> dict[str, Any]`; it invokes staging first, invokes cleanup after the stage operation returns (including a partial per-torrent result), and returns aggregate stage/cleanup fields for one final JSON event.
- The runtime CLI stages and writes receipts, then processes due receipts. Cleanup operates only on successfully staged receipt entries; it does not depend on local Arr import completion.
- Emit `sync_run_summary` with aggregate stage/cleanup counts and reason counts only.

- [x] **Step 1: Write failing order and summary tests**
  - Assert the stage callback runs before cleanup.
  - Assert cleanup still runs after a partial stage result so a separate successfully staged receipt can proceed, while failed torrents have no receipt.
  - Assert the combined summary contains progress/removal/block counts but no per-torrent identifiers, names, or paths.
  - Assert a fatal stage runtime error prevents cleanup.
- [x] **Step 2: Run the focused orchestration tests and verify RED**
  - Run the new orchestration tests by name in `tests/test-ultra-media-cleanup.py`.
  - Expected: fail because the combined runner and summary do not yet exist.
- [x] **Step 3: Implement the ordered runner**
  - Call the existing staging and cleanup runtime functions in order.
  - Preserve per-torrent receipts and cleanup locks; do not let a partial transfer produce a receipt.
  - Return a safe aggregate summary and a failing process status if either phase reports failures.
- [x] **Step 4: Run focused and full Python tests**
  - Expected: orchestration order, partial-failure isolation, JSON redaction, and all existing Python tests pass.

### Task 3: Consolidate NixOS scheduling into one worker

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Remove: `modules/nixos/ultra-media-cleanup.nix`
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py` and `modules/nixos/scripts/ultra-media-cleanup.py` (remove the obsolete retry-reset mode/helper)
- Remove: `docs/superpowers/specs/2026-11-19-drlight-cleanup-retry-reset.md`
- Remove: `docs/superpowers/plans/2026-11-19-drlight-cleanup-retry-reset.md`
- Remove: `docs/superpowers/specs/2026-11-19-drlight-per-torrent-cleanup.md`
- Remove: `docs/superpowers/plans/2026-11-19-drlight-per-torrent-cleanup.md`
- Test: `tests/test-media-center-archetype.nix`
- Test: `tests/test-ultra-media-cleanup.py`

**Interfaces:**
- Keep `ultra-media-download-stage.service` and its hourly timer as the single scheduled worker; invoke the combined runner after the `/srv/media` mount and Opnix secrets are available.
- Remove the separate `ultra-media-cleanup.service` and `.timer`, cleanup-only Arr API dependencies/groups/config, and the separate retry-reset service/CLI.
- Keep cleanup enablement, remote disk monitoring, and the existing retention policy.

- [x] **Step 1: Add failing Nix archetype assertions**
  - Assert one hourly timer runs the combined sync/cleanup command.
  - Assert no separate cleanup timer/service, no Arr API-key dependencies/groups, and no retry-reset worker remain.
  - Assert the unified worker has only the required secret groups, staging/state write paths, and remote metrics write path when enabled.
- [x] **Step 2: Run the focused archetype check and verify RED**
  - Run `nix build .#checks.x86_64-linux.drlight-media-storage --impure --no-link` before implementation.
  - Expected: new assertions fail against the separate stage and cleanup units.
- [x] **Step 3: Consolidate the NixOS unit**
  - Put stage then cleanup orchestration behind the existing hourly service/timer.
  - Remove the cleanup timer/service and obsolete reset unit/CLI; remove Arr-only dependencies and permissions.
  - Preserve remote disk probe metrics and strict mount, secret, network, filesystem, and account protections.
- [x] **Step 4: Run focused archetype and Python tests**
  - Expected: the Nix archetype check and full cleanup/staging Python suite pass.

### Task 4: Update the Ultra Grafana dashboard and failure alert

**Files:**
- Modify: `modules/nixos/grafana.nix`
- Test: `tests/test-grafana.nix`

**Interfaces:**
- Preserve dashboard UID `drlight-ultra-media-sync` and the existing dashboard URL identity.
- All staging, cleanup, and combined summary Loki queries use the unified worker service label.
- Keep account-level seedbox disk Prometheus metrics and Drlight media filesystem panels.

- [x] **Step 1: Add failing dashboard assertions**
  - Assert progress, cleanup, final summary, and systemd failure queries all use the single service.
  - Assert useful aggregate JSON fields are displayed and no query formats torrent IDs or source paths.
  - Assert disk panels and the 3 TB threshold remain.
- [x] **Step 2: Run the focused Grafana check and verify RED**
  - Run `nix build .#checks.x86_64-linux.nixos-grafana-ultra-download-stage-dashboard --impure --no-link`.
  - Expected: it fails because cleanup panels and alert references still target a separate cleanup service.
- [x] **Step 3: Update dashboard panels and alert wording/query**
  - Display live staging totals/rate/ETA, per-run synced/failed/removal/block counts, retention reasons, current systemd run state, and seedbox disk usage.
  - Keep JSON event formatting readable and aggregate-only.
- [x] **Step 4: Run the focused Grafana check and verify GREEN**
  - Run `nix build .#checks.x86_64-linux.nixos-grafana-ultra-download-stage-dashboard --impure --no-link`.
  - Expected: provisioned dashboard and alert tests pass with the stable UID and one service label.

### Task 5: Final validation and commit

- [x] Run `devenv tasks run check:lint` and the complete Python cleanup/staging test suite.
- [x] Run `devenv tasks run docs:generate-options` because the cleanup option description changed.
- [x] Remove superseded plans/specs for Arr-gated cleanup and the standalone reset worker.
- [x] Review the diff for weakened deletion gates, stale service references, non-JSON logs, high-cardinality metrics, or path/identifier leakage.
- [x] Commit with a conventional Jujutsu description before final Nix validation.
- [x] Run `devenv tasks run test:build-checks` and `devenv tasks run test:all` against the committed tree.

### Task 6: Push the PR update and deploy to Drlight

- [ ] Move the existing PR bookmark `fix/drlight-cleanup-torrent-isolation` to the reviewed commit and push that bookmark with native `jj git push`.
- [ ] Create a Drlight plan with `devenv tasks run machines:plan --input machine=drlight`.
- [ ] Review the plan output; verify the target is exactly Drlight and stop if it contains unexpected broad system/package changes.
- [ ] Apply only the returned plan ID using `devenv tasks run machines:apply --input machine=drlight --input planId=<exact-plan-id>`.
- [ ] Verify the deployment with `devenv tasks run machines:check --input machine=drlight` and confirm the unified sync/cleanup timer and service are healthy.
