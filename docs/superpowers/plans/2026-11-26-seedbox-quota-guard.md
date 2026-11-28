# Seedbox Quota Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Keep Ultra below its account quota by pausing Transmission downloads at 3.8 TB and resuming guard-paused downloads below 3.5 TB, while allowing completed torrents to seed.

**Architecture:** A one-minute systemd timer on Drlight runs a small Python quota guard. It reads live account usage over the existing strict SSH connection, uses Transmission RPC to stop only active/queued incomplete torrents, and persists the hashes it stopped so only those torrents are resumed after cleanup frees space. The existing hourly staging and verified cleanup remain responsible for freeing data; Prometheus/Grafana record the one-week trial.

**Tech Stack:** NixOS modules, Python standard library, Transmission RPC, strict SSH, systemd timers, Prometheus textfile metrics, Grafana.

**Spec:** `docs/superpowers/specs/2026-11-26-seedbox-quota-guard-design.md`

## Global Constraints

- Pause at 3.8 TB decimal; resume below 3.5 TB decimal; poll live quota every minute.
- Stop only incomplete torrents in downloading or queued-to-download states; leave completed torrents seeding.
- Resume only torrent hashes recorded as paused by this guard; do not delete payloads.
- Keep the existing verified staging and cleanup safety gates unchanged.
- If usage or RPC state is unavailable, never resume from stale or unknown usage.
- Never send a Transmission stop/start request with an empty or invalid hash list.
- The current outage requires one-time space recovery and Transmission restoration before the production trial can operate.

## Review Focus

- `quota -p` output includes an over-quota `*` suffix and 1 KiB block counts; test exact byte conversion and malformed output handling.
- Transmission status 3/4 means queued/downloading, while 5/6 means queued/seeding/seeding; prove seeds and pre-stopped torrents are untouched.
- Hysteresis must persist across timer invocations and restarts; prove no resume between 3.5 TB and 3.8 TB and only guard-owned hashes resume below 3.5 TB.
- RPC/probe failures must preserve paused state and never emit a resume action; test failures and corrupted state.
- Week-review metrics must not expose torrent names or hashes; test aggregate-only output and Grafana queries.

---

### Task 1: Add a live account-quota probe

**Files:**
- Modify: `modules/nixos/scripts/ultra_media_file_stat.py`
- Modify: `modules/nixos/scripts/ultra-media-cleanup.py`
- Modify: `tests/test-ultra-media-cleanup.py`

**Interfaces:**
- `parse_quota_usage(output: str) -> dict[str, int] | None` parses the account's `quota -p` row and returns `used_bytes`, converting 1 KiB blocks to bytes and accepting the usage `*` suffix.
- The runtime disk probe uses the fixed remote command `quota -p`; its existing strict host-key and SSH behavior remains unchanged.

- [ ] Add tests for valid quota rows, the over-quota marker, byte conversion, missing rows, and malformed counts; change the existing remote-probe test to expect `quota -p`.
- [ ] Run the focused Python tests and confirm the new quota cases fail before implementation.
- [ ] Implement quota parsing and use it in the existing runtime probe.
- [ ] Run the focused quota and cleanup Python suites; confirm both pass.
- [ ] Run the existing cleanup suite with `python tests/test-ultra-media-cleanup.py modules/nixos/scripts/ultra-media-cleanup.py modules/nixos/scripts/transmission_rpc.py modules/nixos/scripts/ultra-media-download-stage.py modules/nixos/scripts`.
- [ ] Commit the tested probe change.

### Task 2: Implement safe Transmission pause/resume state

**Files:**
- Modify: `modules/nixos/scripts/transmission_rpc.py`
- Create: `modules/nixos/scripts/ultra_media_space_guard.py`
- Create: `tests/test-ultra-media-space-guard.py`

**Interfaces:**
- `TransmissionRPC.stop_torrents(hashes: Sequence[str])` and `start_torrents(hashes: Sequence[str])` use only non-empty lists of explicit 40-hex torrent hashes and the allow-listed `torrent-stop` / `torrent-start` RPC methods.
- `plan_guard_actions(used_bytes, torrents, state, *, pause_at_bytes, resume_below_bytes)` returns the next active state and explicit hashes to pause or resume; only status 3/4 incomplete torrents are pause candidates.
- The guard persists `version`, `active`, `paused_hashes`, and pause/resume/probe-failure/RPC-failure totals in an atomic JSON state file; logs and metrics omit torrent identities.
- Run the focused suite with `PYTHONPATH=modules/nixos/scripts python tests/test-ultra-media-space-guard.py`.

- [ ] Add failing tests for threshold entry, hysteresis, seeding/pre-stopped exclusions, newly queued downloads while guarded, guard-owned-only resume, invalid/empty hash lists, corrupted state, and RPC/probe failure behavior.
- [ ] Run the focused Python suite and confirm the new state/RPC tests fail before implementation.
- [ ] Add narrowly allow-listed stop/start operations to `TransmissionRPC` and preserve validated status in normalized torrent records.
- [ ] Implement the pure transition planner, atomic state handling, one-cycle runner, and aggregate Prometheus renderer.
- [ ] Run the focused Python suites and confirm guard actions, persistence, and failure cases pass.
- [ ] Commit the tested guard and RPC behavior.

### Task 3: Wire the guard into Drlight's NixOS configuration

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `machines/drlight/default.nix`
- Modify: `tests/test-media-center-archetype.nix`

**Interfaces:**
- Add `myConfig.ultraMediaDownloadStage.spaceGuard.{enable,pauseAtBytes,resumeBelowBytes}`; require `resumeBelowBytes < pauseAtBytes <= remoteDisk.capacityBytes`, with cleanup and remote-disk monitoring enabled when the guard is enabled.
- Add `ultra-media-space-guard.service` and a one-minute timer, using the existing `ultra-sync` account, strict SSH secrets, Transmission RPC secrets, protected state directory, and metrics directory.
- Enable Drlight's guard at `3_800_000_000_000` pause bytes and `3_500_000_000_000` resume bytes.

- [ ] Add failing module-evaluation assertions for option validation, service hardening, scoped secret access, timer cadence, and Drlight thresholds.
- [ ] Commit the test-only change, run the focused Drlight module check, and confirm it fails on the missing guard configuration.
- [ ] Implement the options, service/timer wiring, secret scope, and Drlight values.
- [ ] Commit the NixOS integration, run the focused media-center module check, and fix any failures before finalizing the commit.

### Task 4: Publish week-review telemetry in Grafana

**Files:**
- Modify: `modules/nixos/ultra-media-download-stage.nix`
- Modify: `modules/nixos/grafana.nix`
- Modify: `tests/test-grafana.nix`
- Modify: `tests/default.nix`
- Create: `tests/test-ultra-media-space-guard.nix`

**Interfaces:**
- Publish a separate atomic textfile metrics file containing live used bytes, guard-active state, paused-torrent count, pause/resume totals, probe/RPC failure totals, and sample time.
- Use aggregate metrics only: `ultra_seedbox_download_guard_used_bytes`, `ultra_seedbox_download_guard_active`, `ultra_seedbox_download_guard_paused_torrents`, and pause/resume/failure counters; never label samples with torrent identity.
- Add Grafana panels for live quota usage with 3.5/3.8 TB markers and guard state/activity; do not add torrent labels or hashes.
- Register the focused Python guard suite in the repository's Nix checks.

- [ ] Add failing generated-dashboard checks for the live quota query, pause/resume thresholds, and aggregate guard metrics.
- [ ] Commit the test-only change, run the focused Grafana dashboard check, and confirm it fails on missing guard panels.
- [ ] Wire the separate metrics file into node-exporter permissions and add the dashboard panels.
- [ ] Register the focused Python guard check, commit the implementation, and run the Python guard, Grafana dashboard, and Drlight module checks; fix any failures before finalizing the commit.

### Task 5: Validate and prepare the production trial

- [ ] Run `devenv tasks run check:lint`.
- [ ] Run `devenv tasks run test:build-checks`, `devenv tasks run test:eval`, and `devenv tasks run test:all` after committing the Nix changes.
- [ ] Review the complete diff; confirm no seedbox files were deleted and no direct seedbox service changes were made.
- [ ] Create a plan for exactly `drlight` with `devenv tasks run machines:plan --input machine=drlight` and inspect its complete output for unexpected changes.
- [ ] Apply only the reviewed plan after confirming the seedbox Transmission RPC is reachable; then run `devenv tasks run machines:check --input machine=drlight`.
- [ ] Review quota, guard transitions, pause duration, cleanup, and probe/RPC failures after one week of production metrics.
