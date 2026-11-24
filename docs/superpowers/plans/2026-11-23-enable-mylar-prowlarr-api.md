# Enable Mylar–Prowlarr Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Drlight Mylar's API using the user's Opnix field and sync comic indexers from local Prowlarr.

**Architecture:** Reference `Mylar3/api-key` from the default Opnix vault, deliver it only to `/run/secrets/mylar3-api-key`, and let the existing Mylar INI renderer write API-enabled settings into its mode-`0600` runtime configuration. After a Drlight-only reviewed deployment, add Mylar to Prowlarr at loopback with Full Sync and the comics category `7030`.

**Tech Stack:** NixOS, Mylar3, Opnix, Prowlarr v3 API, Jujutsu, Devenv Machines.

**Spec:** `docs/superpowers/specs/2026-11-23-drlight-media-automation-design.md`

## Global Constraints

- Use the `Mylar3/api-key` field in the machine's default Opnix vault; do not copy the value into Nix, logs, command arguments, or chat.
- Runtime secret file: `/run/secrets/mylar3-api-key`, owner `root`, group `media-auth-mylar3`, mode `0440`, service consumer `mylar3`.
- Keep the Mylar configuration file mode `0600`; the Mylar config renderer already supports runtime secret paths.
- Mylar is configured for Western comics, not manga. Do not add or install a manga manager in this change.
- Keep Mylar's existing torrent downloader/search settings disabled. Only configure Prowlarr indexer synchronization.
- Deploy only Drlight through a fresh reviewed Machines plan; apply only its exact plan ID.

## Review Focus

- The Opnix reference is empty, ambiguous, or unavailable — fail before writing a placeholder or secret value; test through Prowlarr after deployment.
- The secret is exposed in Nix store content, generated logs, or shell output — assert the Nix settings contain only the runtime file path and keep the key out of command output.
- Mylar's service user cannot read the runtime key — assert the file group, mode, supplementary group, and unit ordering in the media-center evaluation.
- Existing Mylar torrent behavior changes as a side effect — assert both torrent switches remain disabled.
- Comic indexers are synced using inappropriate categories — configure and verify only category `7030` (`Books/Comics`).

---

### Task 1: Declare Mylar's runtime API secret

**Files:**
- Modify: `modules/nixos/media-app-reconciliation.nix`
- Modify: `modules/nixos/media-management.nix`
- Modify: `tests/test-media-center-archetype.nix`

**Interfaces:**
- Consumes: Existing `services.mylar3.settings` secret renderer and `Mylar3/username` + `Mylar3/password` Opnix pattern.
- Produces: Opnix secret `mylar3ApiKey` referencing `Mylar3/api-key`, runtime path `/run/secrets/mylar3-api-key`, and `services.mylar3.settings.API.API_ENABLED` / `API.API_KEY.secret`.

- [ ] **Step 1: Add failing media-center assertions**

Assert API enablement, the runtime key path, the unqualified Opnix reference and its resolved `op://Opnix/Mylar3/api-key`, root ownership, `media-auth-mylar3` group, mode `0440`, `mylar3` service trigger, and unchanged disabled torrent/search settings.

- [ ] **Step 2: Confirm RED**

Run: `nix build .#checks.x86_64-linux.media-center-archetype --no-link --impure`

Expected: fail on the missing Mylar API settings and Opnix API-key secret assertions.

- [ ] **Step 3: Add the runtime-only secret and API settings**

Declare the new secret alongside the existing media auth secrets, accessible to the Mylar service group only. Add `API_ENABLED = true` and `API_KEY.secret = "/run/secrets/mylar3-api-key"` under Mylar settings. Do not set or modify Mylar torrent/download switches.

- [ ] **Step 4: Verify focused checks**

Run: `nix build .#checks.x86_64-linux.media-center-archetype --no-link --impure`

Expected: pass, including the runtime secret path and preserved torrent-disabled assertions.

Run: `nix build .#checks.x86_64-linux.media-app-api-reconciliation --no-link --impure`

Expected: pass; existing `MylarConfigTests` confirm secret expansion and mode-`0600` config output.

### Task 2: Validate and deploy the Mylar API setting

**Files:**
- No additional production files.

- [ ] **Step 1: Commit the Nix/test change before final Nix validation**

Use a conventional Jujutsu description such as `feat: enable Mylar API through Opnix`.

- [ ] **Step 2: Run repository validation**

Run `devenv tasks run check:lint` and `devenv tasks run test:build-checks`. Expected: both pass. Before planning, resolve `op://Opnix/Mylar3/api-key` with `op read` while suppressing its value; stop if the CLI is unauthenticated or times out, and do not place the key in a command argument or output.

- [ ] **Step 3: Generate and review a Drlight-only plan**

Run `devenv tasks run machines:plan --input machine=drlight`. Confirm the plan targets only Drlight and contains only the Mylar runtime secret/API configuration changes. Stop on unexpected package, firewall, storage, or other-machine changes.

- [ ] **Step 4: Apply only the reviewed plan and check the target**

Apply using the exact plan ID, then run `devenv tasks run machines:check --input machine=drlight`. Expected: Mylar remains active, its API setting is enabled, and the runtime key is present without printing it.

### Task 3: Connect Mylar to Prowlarr for comics

**Files:**
- No repository files; this is operator-managed Prowlarr runtime state.

- [ ] **Step 1: Test the Mylar application connection**

Read Mylar's API key from its runtime config on Drlight without printing it. Test `http://127.0.0.1:8090` from Prowlarr with Full Sync and category `7030`. Expected: the Prowlarr application test returns HTTP 200.

- [ ] **Step 2: Add Mylar to Prowlarr**

Create or update the Mylar application with Prowlarr URL `http://127.0.0.1:9696`, Mylar URL `http://127.0.0.1:8090`, `syncLevel=fullSync`, and `syncCategories=[7030]`. Keep the API key out of output.

- [ ] **Step 3: Verify comic provider synchronization**

Trigger Prowlarr's `ApplicationIndexerSync` command and verify only indexers supporting `7030` are synced to Mylar, the application remains enabled/full-sync, and Mylar's torrent search/download settings remain disabled. If no current indexer supports `7030`, report the empty match rather than changing indexer categories.
