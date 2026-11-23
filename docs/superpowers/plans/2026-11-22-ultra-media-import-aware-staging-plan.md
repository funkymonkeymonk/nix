# Import-Aware Ultra Media Staging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent the Ultra staging worker from re-copying torrents whose media is already confirmed in Radarr, Sonarr, or Lidarr after local staging cleanup.

**Architecture:** Collect the Transmission `hashString` as Arr's `downloadId`, reuse the existing `collect_statuses` queries, and add a failure-closed per-torrent staging decision. Numeric Transmission IDs remain the internal staging/receipt key. A torrent is skipped only when Arr status confirms imported content; unknown, failed, or unavailable status remains stageable.

**Tech Stack:** Python standard library, existing Arr status clients, Nix-packaged test derivations.

**Spec:** `docs/superpowers/specs/2026-11-22-ultra-media-import-aware-staging-design.md`

## Global Constraints

- Do not treat cleanup receipts as proof of successful Arr import.
- Do not delete staged files automatically in this change.
- Do not move files directly into media libraries.
- Status collection failures remain failure-closed and preserve retry behavior.

## Review Focus

- Imported torrent with missing staged files must be skipped rather than recopied.
- Failed or partially imported torrent must remain eligible for staging retry.
- Arr API outage or malformed status must not suppress staging.
- Multiple Arr applications reporting mixed status must not produce a false success.
- Existing metrics and remote cleanup receipt creation must remain unchanged.

---

### Task 1: Define the import-aware staging decision

**Files:**
- Modify: `modules/nixos/scripts/transmission_rpc.py`
- Modify: `modules/nixos/scripts/media-library-status.py`
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Test: `tests/test-ultra-media-cleanup.py`
- Test: `tests/test-media-library-status.py`

**Interfaces:**
- Consumes: Transmission records with numeric `id` and validated 40-character hexadecimal `download_id`; Arr history queries use the hash as `downloadId`.
- Produces: a focused helper, `torrent_is_imported(torrent_id: int, library_statuses: Mapping[str, tuple[int, int]] | None) -> bool`, used before transfer planning.

- [x] **Step 1: Write failing tests**

  Add tests that Transmission requests and normalizes `hashString`, and that `collect_statuses` queries Arr using the hash while retaining numeric torrent ID as its output key. Test lowercase Arr import history event names, explicit failed import events, and failed/unknown status precedence across clients. Add staging-helper tests for imported status `1`, failed `0`, unavailable `-1`, missing status, and mixed/unknown status. Assert only confirmed imported status returns true.

- [x] **Step 2: Run the focused test derivation and confirm RED**

  Run `devenv tasks run test:build-checks` or the focused `test-ultra-media-cleanup` derivation. Expected: the new helper tests fail because the helper does not yet exist.

- [x] **Step 3: Implement `torrent_is_imported(...)`**

  Return true only for an explicit imported value of `1`; return false for `0`, `-1`, missing keys, malformed values, or absent mappings.

- [x] **Step 4: Run the focused tests and confirm GREEN**

  Run the focused test derivation and verify all new status-decision tests pass.

- [x] **Step 5: Commit**

  Use `jj describe -m "feat: add import-aware staging decision"`.

### Task 2: Skip confirmed imports without changing retries

**Files:**
- Modify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Test: `tests/test-ultra-media-cleanup.py`

**Interfaces:**
- Consumes: `torrent_is_imported(...)` from Task 1 and existing staging transfer plans.
- Produces: stage-cycle behavior that excludes confirmed imported torrents before transfer while preserving metrics, receipts, and retry behavior for all other torrents.

- [x] **Step 1: Add failing staging-cycle tests**

  Exercise `stage_completed_downloads` with a confirmed imported torrent whose local destination is absent and assert no transfer occurs; exercise failed and unavailable statuses and assert transfer planning still occurs. Assert receipt creation is unchanged for actually staged torrents.

- [x] **Step 2: Run tests and confirm RED**

  Run the focused Python test derivation and verify the imported-torrent case still attempts staging.

- [x] **Step 3: Implement the minimal skip path**

  Filter confirmed imported torrents before transfer planning. Count them separately if existing result fields support it; do not mark them as staged or create cleanup receipts. Preserve existing `torrents_total` and status metrics semantics unless the tests require a new explicit skipped counter.

- [x] **Step 4: Run tests and confirm GREEN**

  Run the focused Python test derivation and verify imported, failed, unavailable, receipt, and metric cases pass.

- [x] **Step 5: Commit**

  Use `jj describe -m "fix: avoid restaging imported torrents"`.

### Task 3: Validate formatting and repository checks

**Files:**
- Verify: `docs/superpowers/specs/2026-11-22-ultra-media-import-aware-staging-design.md`
- Verify: `modules/nixos/scripts/ultra-media-download-stage.py`
- Verify: `tests/test-ultra-media-cleanup.py`

- [x] **Step 1: Run formatter and lint**

  Run `devenv tasks run check:lint`; fix only relevant formatting or static-analysis findings.

- [ ] **Step 2: Run build checks**

  Run `devenv tasks run test:build-checks` and verify the affected test derivation passes.

- [ ] **Step 3: Run the full required suite**

  Run `devenv tasks run test:all` because this changes a Drlight NixOS service script and its test wiring.

  Validation note: the affected `media-library-status` and `drlight-ultra-media-cleanup` derivations pass directly. The full `test:build-checks` and dependent `test:all` remain blocked by the unrelated `drlight-media-storage` check failing during VM shutdown (`dnsmasq: exiting on receipt of SIGTERM`).

- [ ] **Step 4: Review the final diff and advance JJ**

  Run `jj diff --summary`, describe the final change with a conventional commit message, and run `jj new`.
