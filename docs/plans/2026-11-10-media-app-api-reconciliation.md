# Declarative Media Application Reconciliation Implementation Plan

> **Note:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add reusable, runtime-safe API reconciliation for the Drlight media applications and explain the pattern for future services.

**Architecture:** NixOS-native service options own process-level settings. Per-app reconciliation oneshots apply only explicitly declared database/API resources, using a shared Python HTTP/secret utility and service-specific adapters. Mylar3 uses a typed, runtime-generated INI because it does not expose the same Servarr API.

**Tech Stack:** NixOS modules, systemd oneshots, Python 3 standard library, Nix eval/runCommand tests, Markdown ADR/explanation docs.

---

### Task 1: Lock down observable reconciliation outcomes with tests

**Files:**
- Modify: `tests/test-media-center-archetype.nix`
- Create: `tests/test-media-app-reconciliation.py`
- Modify: `tests/default.nix`

**Step 1: Write assertions first**

Assert the desired Drlight state: one API sync unit per Arr service, the Transmission endpoint and credentials passed only as file references, declared roots and staging path mapping, Bazarr's local Arr connections, and typed Mylar3 settings. The Python test starts a local fake HTTP API and checks idempotent create/update, schema-default preservation, duplicate-match failure, and absence of delete requests.

**Step 2: Run only the new tests and record expected failures**

Run the targeted Nix check and Python test. Confirm failure occurs because the new settings/module/script are absent, not because of test harness errors.

### Task 2: Implement common API and secret primitives

**Files:**
- Create: `modules/nixos/scripts/media_api_reconcile.py`
- Create: `modules/nixos/scripts/servarr_reconcile.py`

Implement bounded HTTP requests, API key extraction from config XML, runtime secret expansion, safe error messages, and Arr schema-driven download-client create/update plus root-folder and remote-path mapping ensure operations. Preserve unknown fields and API-generated IDs. Never implement delete/prune.

### Task 3: Implement Bazarr adapter

**Files:**
- Create: `modules/nixos/scripts/bazarr_reconcile.py`

Read Bazarr and Arr API keys at runtime. Update only the declared Sonarr and Radarr connection keys through Bazarr's own API. Fail if the settings document is malformed; preserve unrelated Bazarr settings.

### Task 4: Add NixOS reconciliation services

**Files:**
- Create: `modules/nixos/media-app-reconciliation.nix`
- Modify: `modules/nixos/media-management.nix`
- Modify: `library/machines/catalog.nix` only if module composition requires it

Declare per-app desired state. Generate JSON containing only non-secret values and secret file paths. Create oneshots that wait for app services, run as the app user, and are wanted by the corresponding service. Derive Transmission RPC host/port/TLS/base URL at runtime from the configured RPC URL secret file. Configure Radarr/Sonarr/Lidarr's Transmission client category, local root, and exact remote-path mapping to staging. Configure Bazarr to use Drlight-local Sonarr and Radarr.

### Task 5: Add typed Mylar3 declarative INI support

**Files:**
- Modify: `modules/nixos/mylar3.nix`
- Modify: `tests/test-media-app-reconciliation.py`
- Modify: `tests/test-media-center-archetype.nix`

Expose only upstream-supported settings needed for the local comics destination, interface/auth, and configured downloader behavior. Render the INI at runtime before Mylar3 starts so secret values never enter the Nix store. Keep the installed Mylar3 API and database state intact. Test the renderer with temporary files and ensure file mode/owner are restrictive.

### Task 6: Integrate tests and docs

**Files:**
- Modify: `tests/default.nix`
- Modify: `docs/explanation/index.md`
- Create: `docs/explanation/api-reconciliation.md`
- Create: `docs/adr/0003-declarative-media-app-reconciliation.md`
- Create: `docs/superpowers/specs/2026-11-10-media-app-api-reconciliation-design.md`
- Create: `docs/plans/2026-11-10-media-app-api-reconciliation.md`
- Modify: `docs/how-to/migrate-ultra-media-apps-to-drlight.md`

Explain the reusable pattern, ownership rules, secret handling, systemd ordering, test approach, and how a future adapter declares resource identity and update semantics. Update the migration runbook to replace manual UI steps only for configuration now managed by Nix; retain explicit manual/cutover steps for Ultra Prowlarr and live endpoint verification.

### Task 7: Verify, review, and publish the stacked PR

Run `devenv tasks run check:lint`, targeted API and Nix tests, `devenv tasks run test:build-checks`, `devenv tasks run test:eval`, and `devenv tasks run test:all` as time permits. Inspect the Nix/JJ diff and secret references. Commit as a conventional commit, create a child bookmark on top of PR #545, push fast-forward, and open a GitHub PR targeting the PR #545 branch. Never deploy or call live Ultra APIs.
