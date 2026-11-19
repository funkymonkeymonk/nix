# Drlight Sync Lag and Remote Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline execution authorized). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Report trustworthy rsync progress, stage dated completed torrents oldest-first, expose backlog age, and alert in Grafana when Ultra account storage exceeds 3 TB.

**Architecture:** Parse rsync progress from stdout; request Transmission `doneDate` and sort eligible torrents oldest-first. Emit aggregate oldest-pending age. The cleanup worker polls Ultra's `app-stats` command over existing strict SSH every minute, logs aggregate usage, and atomically publishes Prometheus textfile metrics. Grafana shows the metrics and provisions a warning rule routed through the existing null Alertmanager receiver.

**Tech Stack:** Python, Transmission RPC, NixOS systemd, Ultra `app-stats`, node_exporter textfile collector, Prometheus, Alertmanager, Grafana, Jujutsu.

**Spec:** `docs/superpowers/specs/2026-11-17-drlight-sync-lag-storage-design.md`

## Global Constraints

- Keep torrent names, IDs, media paths, remote host values, and secrets out of all logs and Prometheus labels.
- Preserve the existing whole-torrent staging/cleanup, ownership, retry, import, and revalidation gates.
- Do not stage a completed torrent with missing/invalid completion time; report the unknown count and make time-behind unknown while any remain.
- Use decimal bytes: 4,000,000,000,000 capacity and 3,000,000,000,000 warning threshold.
- Keep notifications routed to the existing null receiver; add no external receiver or webhook secret.
- Disk-probe failure must not block cleanup, and stale telemetry must not appear as safe/under-threshold.

## Review Focus

- Rsync progress on stdout is parsed; stderr diagnostics are discarded.
- `doneDate` is validated; dated torrents are sorted oldest-first; unknown timestamps are surfaced and never silently staged out of order.
- Lag age advances during a transfer and steps down after older torrents stage; unknown dates make the metric unknown.
- Remote usage comes from account-level `app-stats`, not shared-filesystem `df`; table parsing rejects malformed data.
- Empty queues still sample disk usage; unavailable disk samples do not prevent cleanup or preserve stale metrics as current.
- Prometheus textfile metric permissions permit node_exporter read and cleanup-worker atomic updates, with no unsafe world-writable path.
- The 3 TB alert fires from a fresh usage sample and staleness is separately observable; both route to null.

---

### Task 1: Fix rsync progress stream

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Test: `tests/test-ultra-media-cleanup.py`

- [ ] Change the runner test to emit progress2-shaped records on stdout and diagnostics on stderr; assert only byte counts are reported.
- [ ] Run the focused Python suite and confirm the stdout regression fails against the current runner.
- [ ] Pipe stdout and parse numeric progress only; discard stderr, preserving heartbeat and exit-code handling.
- [ ] Run the focused Python suite and verify it passes.

### Task 2: Order staging and report backlog age

**Files:**
- Modify: `modules/nixos/scripts/transmission_rpc.py`
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Test: `tests/test-ultra-media-cleanup.py`

- [ ] Add `doneDate` to the read-only RPC field request and normalize valid positive completion timestamps.
- [ ] Add RED tests for oldest-first ordering, stable ties, invalid/missing timestamps being skipped and counted, backlog-age updates after staging, and unknown lag when unorderable candidates remain.
- [ ] Sort planned transfers by completion timestamp ascending; emit only aggregate `time_behind_seconds` and unknown-order count.
- [ ] Run the focused Python suite and verify ordering, fail-closed timestamps, and lag behavior.

### Task 3: Probe account storage and publish metrics

**Files:**
- Modify: `modules/nixos/scripts/ultra_media_file_stat.py`
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Modify: `modules/nixos/ultra-media-cleanup.nix`
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Test: `tests/test-ultra-media-cleanup.py`
- Test: `tests/test-media-center-archetype.nix`

- [ ] Add tests parsing the documented `app-stats show -s disk -t hour -c 1` table to decimal used bytes and rejecting missing/malformed rows.
- [ ] Add tests for strict-SSH command construction and safe failure without logging endpoint/path details.
- [ ] Add the one-minute cleanup probe before the empty-queue early return; failures emit a safe unavailable event and do not stop queue processing.
- [ ] Write the `.prom` snapshot atomically to a private group-readable textfile directory; add the textfile collector and least-privilege group/permissions for cleanup and node_exporter.
- [ ] Run focused cleanup and media-storage checks.

### Task 4: Add Grafana panels and Prometheus warning

**Files:**
- Modify: `modules/nixos/grafana.nix`
- Modify: `modules/nixos/prometheus.nix`
- Test: `tests/test-grafana.nix`
- Test: relevant Prometheus observability tests

- [ ] Add RED assertions for the oldest-pending-age panel, remote used/capacity panel, 3 TB alert threshold, null receiver wiring, and safe labels.
- [ ] Add Grafana history/stat panels, a Prometheus alert rule at 3,000,000,000,000 bytes, and an explicit stale-sample alert; preserve null routing.
- [ ] Run focused Grafana, Prometheus, and Drlight module checks.

### Task 5: Validate and prepare the change

- [ ] Run `devenv tasks run check:lint`.
- [ ] Run `devenv tasks run test:all`.
- [ ] Request a fresh read-only code review and resolve important findings.
- [ ] Commit in this Jujutsu workspace. Ask before pushing/opening a PR or deploying; deployment uses a reviewed Machines plan unless separately authorized.
