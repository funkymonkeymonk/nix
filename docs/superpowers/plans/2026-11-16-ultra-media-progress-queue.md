# Ultra Media Progress and Concurrent Cleanup Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Report staging progress and clean eligible torrents as soon as each complete torrent has been staged and verified, without waiting for the whole batch.

**Architecture:** Stage each torrent atomically, publish a private idempotent receipt after all of its files are copied, and have a one-minute cleanup queue worker process only receipted torrents while the stage loop continues. Per-torrent locks serialize stage/removal of the same torrent; full-inventory ownership checks and immediate revalidation remain mandatory. Emit aggregate JSON progress to journald every 60 seconds and graph it in the existing Grafana dashboard.

**Tech Stack:** Python, NixOS systemd `Type=exec` staging plus oneshot/timer cleanup, Transmission read-only RPC plus guarded remove RPC, Vector/Loki/Grafana, Jujutsu.

**Spec:** `docs/superpowers/specs/2026-11-16-ultra-media-progress-queue-design.md`

## Global Constraints

- Transmission cleanup remains whole-torrent only; every file belonging to that torrent must pass the existing import and size/mtime checks.
- Preserve retention thresholds, tracker policy, source-ownership checks, full-inventory collision accounting, and fresh revalidation immediately before removal.
- Only a fully transferred and published torrent gets a queue receipt. A failure in another torrent does not invalidate an already completed torrent's receipt.
- Reuse a stable hash-named per-torrent rsync workspace only when its manifest fingerprint matches; the currently active legacy random workspace cannot be resumed and may be recopied from the untouched source after an authorized restart.
- Reuse an existing published stage file only after strict remote stat confirms a regular file with matching size and nanosecond mtime; do not checksum or trust size alone.
- Queue state and locks must not expose torrent IDs, media paths, or fingerprints in logs; progress logs contain aggregate values only.
- Cleanup stays disabled/report-only when its existing option is disabled.
- Do not apply a new generation while the current staging service is active without explicit approval to interrupt that run.

## Review Focus

- Partial/mismatched transfers never create an actionable receipt; test failed rsync and fingerprint mismatch.
- A queued torrent is not cleaned while any associated file is missing, mismatched, unimported, below policy, or shared; keep the current full-snapshot ownership checks.
- Stage and cleanup may overlap only for different torrents; cleanup must skip/defer a busy same-torrent lock instead of blocking other receipts. Test both cases.
- Worker retries and crashes are idempotent; test retry-pending, already-removed, stale receipt, and restart behavior.
- Progress/ETA logs are aggregate-only and handle unknown/zero sizes and startup before a stable rate exists.

---

### Task 1: Add staging plan and 60-second aggregate progress events

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Test: `tests/test-ultra-media-cleanup.py`

**Interfaces:**
- Produce a staging plan from one normalized Transmission snapshot, with each planned torrent's internal ID and transfer list plus aggregate torrent/file/byte totals. Raw paths stay internal and never enter logs.
- Add a progress reporter with `started`, periodic `progress`, `torrent_staged`, `deferred`, `failed`, and final `completed` events. Emit only aggregate counters, elapsed time, byte rate, and ETA.

- [x] Add tests that plan totals include only completed, fully mapped transfers and that every file size is counted once.
- [x] Add tests that a progress event is emitted at 60 seconds, includes cumulative bytes/files and a meaningful ETA only after a rate sample, and omits media identifiers/paths/secrets.
- [x] Run `nix build .#checks.x86_64-linux.drlight-ultra-media-cleanup --no-link --impure`; confirm the new tests fail for the missing progress behavior.
- [x] Implement the plan/progress helpers and instrument the stage transfer loop. Capture progress without exposing rsync output; write structured JSON lines to stdout for journald.
- [x] Run the focused check and confirm it passes.

### Task 2: Add private per-torrent receipt and locking primitives

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Test: `tests/test-ultra-media-cleanup.py`

**Interfaces:**
- `write_staged_torrent_receipt(queue_root, torrent_id, fingerprint, staged_at_ns)` atomically records a fully published torrent; duplicate writes are idempotent. The fingerprint covers ordered source paths, sizes, and normalized mapping.
- `read_pending_torrent_receipts(queue_root, now_ns)` returns only due, valid receipt records without logging their IDs or fingerprints.
- `torrent_operation_lock(runtime_root, torrent_id)` derives its lock filename from a one-way hash of the torrent ID under `/run/ultra-media/locks`.
- Queue receipts are stored under `/var/lib/ultra-media/cleanup-queue`; retry backoff starts at 60 seconds and caps at one hour.

- [x] Add tests for receipt permissions/schema under `/var/lib/ultra-media/cleanup-queue`, idempotent replacement, fingerprint mismatch, due-time/backoff handling, and hashed lock filenames under `/run/ultra-media/locks`.
- [x] Run the focused check and confirm the receipt/lock tests fail before implementation.
- [x] Implement the private queue/state directory and per-torrent locks. Use atomic file replacement and safe receipt parsing; malformed records fail closed.
- [x] Run the focused check and confirm it passes.

### Task 3: Queue cleanup per staged torrent while preserving all gates

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Test: `tests/test-ultra-media-cleanup.py`

**Interfaces:**
- Staging acquires the per-torrent lock, transfers and atomically publishes every file for that torrent, then writes its receipt before releasing the lock.
- Cleanup reads due receipts, fetches the full Transmission/Arr snapshot, computes source/local ownership over the full inventory, and evaluates only the receipt's matching torrent fingerprint. It re-fetches and revalidates that candidate under the same per-torrent lock immediately before removal.
- Successfully removed or already-absent torrents are acknowledged. Temporarily unimported candidates remain queued for a later pass; transient failures use exponential retry backoff starting at 60 seconds, while policy-blocked receipts retry no more often than hourly. A new staging receipt resets that torrent's retry state.

- [x] Add tests that cleanup processes only queued IDs and does not remove an unqueued eligible torrent.
- [x] Add tests that another torrent sharing a source path blocks deletion even if that other torrent is not queued.
- [x] Add tests that a partially staged torrent has no receipt, a not-yet-imported receipt remains pending, later import success permits removal, and a later unrelated staging failure does not cancel a completed receipt.
- [x] Add tests that a matching per-torrent workspace resumes rsync partial data, a changed fingerprint purges/restarts only that workspace, and legacy random workspaces are safely discarded after an interrupted service.
- [x] Add tests that existing staged files are reused only after matching remote size and nanosecond mtime; missing/mismatched files are recopied.
- [x] Add concurrency tests proving same-torrent stage/cleanup operations serialize while distinct torrent operations can overlap.
- [x] Add retry/idempotency tests for stale fingerprints, missing torrents, worker interruption, and blocked policy reasons.
- [x] Run the focused check and confirm new queue behavior tests fail before implementation.
- [x] Refactor the staging loop to publish and enqueue each torrent independently; refactor cleanup to drain receipts and retain every existing delete gate.
- [x] Run the focused check and confirm it passes.

### Task 4: Wire the one-minute worker and observability dashboard

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `modules/nixos/ultra-media-cleanup.nix`
- Modify: `modules/nixos/grafana.nix`
- Test: `tests/test-media-center-archetype.nix`
- Test: `tests/test-grafana.nix`

- [x] Add Nix assertions that staging no longer has whole-run `OnSuccess`, cleanup has a one-minute timer only when enabled, and the cleanup unit no longer waits for the stage unit.
- [x] Add a Nix regression assertion that the long-running staging service is `Type=exec`, so system activation waits for executable startup rather than transfer completion.
- [x] Add dashboard tests for progress bytes/percent, rate, ETA, and last event time using aggregate journal events.
- [x] Run the focused Nix checks and confirm the new assertions fail before changing service wiring.
- [x] Configure `StateDirectory=ultra-media` and `StateDirectoryMode=0700` for both stage and cleanup so they share the persistent queue; wire per-torrent runtime locks and a cleanup timer with `OnBootSec=1min` and `OnUnitActiveSec=1min`. Preserve the 60-second progress interval and service sandboxing.
- [x] Update Grafana to visualize aggregate progress, queue/deletion counts, and stale progress without including media identifiers.
- [x] Run the focused Nix checks and confirm they pass.

### Task 5: Validate and prepare the PR update

**Files:**
- Review all changed files in this plan.

- [x] Run `devenv tasks run check:lint`.
- [x] Commit the implementation in the current Jujutsu PR workspace, then run `devenv tasks run test:all`.
- [x] Request a fresh read-only review and resolve any important findings.
- [ ] Push the update to PR 569 with Jujutsu.
- [x] Do not deploy over the active Drlight staging run without authorization; the user explicitly authorized the interruption, and deployment must still use a reviewed Machines plan/apply.
