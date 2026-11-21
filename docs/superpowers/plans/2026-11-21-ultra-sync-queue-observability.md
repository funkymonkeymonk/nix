# Ultra Sync Queue Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish live per-torrent sync metrics and add Grafana panels for current state, queue order, sizes, and ETAs.

**Architecture:** Extend the existing Ultra staging worker to atomically write a Prometheus textfile snapshot containing aggregate and per-torrent gauges. Grafana will query those metrics directly for stat panels and a sortable table, while existing Loki logs remain the detailed run-history source.

**Tech Stack:** Python, Prometheus textfile exposition, NixOS systemd, Grafana JSON generated from `modules/nixos/grafana.nix`.

**Spec:** `docs/superpowers/specs/2026-11-21-ultra-sync-queue-observability-design.md`

## Global Constraints

- Preserve atomic staging and cleanup behavior.
- Do not expose secret values or full filesystem paths.
- Keep metric cardinality bounded to the current queue and replace old rows.
- Treat torrent names as acceptable labels for this internal Prometheus/Grafana deployment.

## Review Focus

- Unknown torrent sizes or transfer rate: metrics must use explicit zero/unknown-safe values and Grafana must not show false ETAs.
- A queue item is incomplete or unmapped: it must not be presented as publishable or given a misleading completion time.
- Metric publication is interrupted: the previous complete snapshot must remain valid.
- A new run replaces an old queue: old per-torrent series must disappear from the snapshot.
- Torrent titles contain Prometheus-special characters: exposition must remain valid and labels must be escaped.

### Task 1: Metric model and exporter tests

**Files:**
- Modify: `tests/test-ultra-media-cleanup.py`
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`

- [ ] Add failing tests for queue ordering, aggregate progress, per-torrent bytes remaining, rate-based ETA, unknown ETA, label escaping, and atomic snapshot replacement.
- [ ] Run the focused Python test suite and confirm the new tests fail for the missing exporter behavior.
- [ ] Implement `render_stage_metrics(...)` and `write_stage_metrics_atomic(...)` with stable metric names and bounded current-queue series.
- [ ] Wire metric updates into staging progress and completion without including filesystem paths or secrets.
- [ ] Run the focused Python tests and confirm they pass.

### Task 2: Runtime wiring and Nix assertions

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `modules/nixos/scripts/ultra-media-sync.py`
- Modify: `tests/test-media-center-archetype.nix`

- [ ] Add a dedicated `/run/ultra-media-metrics/ultra-media-sync.prom` path and pass it to the worker.
- [ ] Ensure the worker creates a valid zero/idle snapshot on startup and updates it during the active run.
- [ ] Add Nix assertions for the runtime metrics path, group permissions, exporter flag, and node-exporter textfile directory integration.
- [ ] Run the focused checks and confirm the generated service configuration is correct.

### Task 3: Grafana dashboard

**Files:**
- Modify: `modules/nixos/grafana.nix`
- Modify: `tests/test-grafana.nix`

- [ ] Add Prometheus stat panels for sync state, torrents published/total, bytes remaining, current rate, and overall ETA.
- [ ] Add a sortable table panel for current torrent title, category, queue position, total bytes, remaining bytes, rate, and ETA.
- [ ] Add stale-data and unknown-value display handling.
- [ ] Add dashboard assertions for the metric names, table columns, and Prometheus datasource.
- [ ] Run Grafana-focused tests and confirm the generated dashboard validates.

### Task 4: Full validation and commit

- [ ] Run `devenv tasks run check:lint`.
- [ ] Run `devenv tasks run test:build-checks`.
- [ ] Run `devenv tasks run test:all`.
- [ ] Describe the JJ change with a conventional commit message and leave an empty JJ working commit ready for deployment.
