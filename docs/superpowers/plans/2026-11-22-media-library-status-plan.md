# Media Library Import Status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add exact Arr import and Jellyfin library status columns to the Drlight media-sync queue dashboard.

**Architecture:** Extend the existing sync metrics snapshot with per-torrent `imported` and `jellyfin` gauges. Arr status comes from history events matched by Transmission `downloadId`; Jellyfin status comes from exact normalized title matching. Grafana displays the gauges as Yes/No/Unknown columns.

**Tech Stack:** Python stdlib HTTP client, NixOS systemd, Prometheus textfile metrics, Grafana HTTP API.

**Spec:** Exact normalized title matching; unmatched values remain No; API failures are Unknown.

## Global Constraints

- Do not expose titles, IDs, or secrets in logs.
- Use existing runtime secret files and the Drlight default vault.
- Preserve the existing hourly sync behavior and fail-closed staging behavior.
- Keep dashboard changes durable through the repository's Grafana provisioning.

## Review Focus

- Arr API failure must produce Unknown rather than false Imported.
- Jellyfin authentication or query failure must produce Unknown.
- Exact normalization must not turn distinct titles into a match.
- Existing per-torrent metrics must remain unchanged.
- Empty and completed queues must publish a valid metrics snapshot.

### Task 1: Status collector

**Files:**
- Create: `modules/nixos/scripts/media-library-status.py`
- Test: `tests/test-media-library-status.nix`

- [ ] Add failing tests for title normalization, Arr imported history matching, Jellyfin exact matching, and Unknown handling.
- [ ] Implement a side-effect-free collector with explicit HTTP clients and bounded requests.
- [ ] Emit `ultra_media_sync_torrent_imported` and `ultra_media_sync_torrent_jellyfin` gauges with the existing queue labels.
- [ ] Run focused tests.

### Task 2: Drlight service wiring

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `modules/nixos/media-app-reconciliation.nix`
- Test: `tests/test-media-center-archetype.nix`

- [ ] Add runtime arguments and service dependencies for Arr API keys and Jellyfin credentials.
- [ ] Keep credentials restricted to the collector service and avoid logging them.
- [ ] Assert generated service arguments, groups, and metric paths.
- [ ] Run the Drlight media checks.

### Task 3: Dashboard

**Files:**
- Modify: `modules/nixos/grafana.nix`
- Modify: API-managed dashboard `drlight-system-health-media-sync`

- [ ] Add Imported and In Jellyfin columns with Yes/No/Unknown mappings.
- [ ] Keep exact title matching visible and preserve ETA sorting.
- [ ] Validate each new PromQL query through `/api/ds/query`.

### Task 4: Verification and deployment

- [ ] Run lint, eval, build checks, and focused tests.
- [ ] Commit with conventional messages.
- [ ] Create and review a Drlight Machines plan.
- [ ] Apply the reviewed plan and verify Prometheus targets and dashboard API state.
