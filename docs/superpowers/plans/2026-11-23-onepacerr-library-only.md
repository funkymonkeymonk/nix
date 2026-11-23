# OnePacerr Existing-Library Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable OnePacerr on Drlight to organize the existing Jellyfin library and update its metadata while leaving downloads disabled and Transmission on Ultra.

**Architecture:** Run OnePacerr `v1.8.16` on Drlight's existing Podman-backed OCI container system. Give it a narrow writable library mount, reach Jellyfin through Podman's host gateway, and inject the existing Opnix-backed Jellyfin credentials through a restricted runtime environment file. Preserve the existing Arr-to-Ultra Transmission RPC and staging configuration unchanged.

**Tech Stack:** NixOS OCI containers with Podman, OnePacerr `v1.8.16`, Jellyfin, Opnix, Python standard library, Nix runCommand evaluation tests.

**Spec:** `docs/superpowers/specs/2026-11-23-drlight-media-automation-design.md`

**Dependency:** Execute after `docs/superpowers/plans/2026-11-23-local-prowlarr-flaresolverr.md`; both plans update separate sections of the migration how-to.

## Global Constraints

- Keep Transmission on Ultra; Radarr/Sonarr/Lidarr continue to manage it through existing Drlight RPC settings and local completed-download staging.
- Set `PIPELINE_SKIP_DOWNLOADS=true`; omit OnePacerr `TORRENT_URL`, `TORRENT_USER`, and `TORRENT_PASSWORD` in this phase.
- Enable existing-file organization and Jellyfin metadata updates, as approved. OnePacerr auto-starts only after the OnePacerr library path and a restorable backup/snapshot are verified.
- Keep the Drlight OnePacerr service disabled and non-autostarting until a read-only Jellyfin admin-auth/library-path preflight passes. Do not guess the Jellyfin library name or start the mutating container until the existing Opnix credentials are verified and the library identity/path is confirmed.
- Pin OnePacerr to `ghcr.io/eltharynd/onepacerr:v1.8.16`, not `latest`.
- Use Drlight's existing Jellyfin admin username/password from the default `Opnix` vault, delivered only through a runtime env file. Never put values in Nix expressions, OCI environment literals, command lines, logs, tests, or docs.
- Use the existing Podman OCI backend; run OnePacerr with a dedicated numeric user in the shared `users` group, mount only the verified target library subtree, use the bridge host gateway for Jellyfin, and publish no container ports.
- Do not enable OnePacerr torrent submission, remove files/torrents, or alter staging/cleanup behavior in this plan.
- Deployment is through the reviewed Drlight Machines workflow. No service activation or library mutation occurs during code validation.

## Review Focus

- OnePacerr accidentally gets a Transmission URL/credentials despite downloads being disabled — assert all `TORRENT_*` values are absent (Tasks 1–2).
- Jellyfin paths differ from container paths — verify the existing series and exact root before setting the path map (Task 3).
- The dedicated OnePacerr UID collides with a host account — reserve UID `1500` only after confirming it remains unused on Drlight (Tasks 1–3).
- Secret values leak into the Nix store, OCI environment literals, or logs — test the runtime env-file renderer and restrict its mode (Tasks 1–2).
- Container-local `localhost` points at OnePacerr, not Jellyfin — use and test `host.containers.internal` through Podman's bridge (Tasks 1–2).
- OnePacerr mutates the wrong series or library root — fail closed when the target series/path is missing and require a backup/snapshot before apply (Task 3).

---

### Task 1: Add failing OnePacerr configuration and secret-rendering tests

**Files:**
- Create: `tests/test-drlight-onepacerr.nix`
- Modify: `tests/default.nix`
- Modify: `tests/test-coverage.nix`

**Interfaces:**
- Consumes: `self.nixosConfigurations.drlight.config` and the existing Opnix Jellyfin credential files.
- Produces: `drlightOnePacerrTest` and a runtime renderer CLI: `onepacerr-env.py --username-file <path> --password-file <path> --output <path>`.

- [ ] **Step 1: Write the failing Nix evaluation test**

Assert Drlight keeps OnePacerr disabled until preflight. In an extended test configuration, enable it with synthetic library values and assert the Podman backend and pinned `v1.8.16` image, `PIPELINE_SKIP_DOWNLOADS=true`, existing-file organization/metadata updates, no `TORRENT_*` variables, host-gateway Jellyfin URL, one narrow library mount, no published ports, UID `1500` with shared `users` GID, runtime env-file path, and systemd ordering after ZFS/Jellyfin/Opnix/admin-auth checks. Also assert Arr Transmission settings, RPC secret paths, and staging roots remain unchanged.

- [ ] **Step 2: Add runtime env-renderer behavior checks**

Use temporary fake Jellyfin credential files and a temporary output path. Assert the renderer writes exactly `JELLYFIN_USERNAME` and `JELLYFIN_PASSWORD`, preserves supported special characters, creates the output with mode `0600`, rejects multi-line values, and never prints credential contents. Keep fixture values synthetic.

- [ ] **Step 3: Register the check and verify RED**

Register `drlight-onepacerr` in `tests/default.nix`, update the OnePacerr coverage comment in `tests/test-coverage.nix`, and stage the new test path so Nix can read it. Run: `nix build .#checks.x86_64-linux.drlight-onepacerr --no-link --impure`.  
Expected: FAIL because OnePacerr is not imported/enabled on Drlight and the runtime env renderer is absent.

### Task 2: Implement the Drlight OnePacerr service in library-only mode

**Files:**
- Modify: `modules/nixos/onepacerr.nix`
- Create: `modules/nixos/onepacerr-env.py`
- Modify: `library/machines/catalog.nix`
- Modify: `tests/test-drlight-onepacerr.nix`

**Interfaces:**
- Consumes: the verified Jellyfin library name/path, existing `/run/secrets/jellyfin-admin-username` and `jellyfin-admin-password`, and the OCI unit `podman-onepacerr.service`.
- Produces: a Drlight-imported OnePacerr module with disabled-by-default activation, explicit host/container library-path options, an Opnix-backed runtime env file, and a tested opt-in container configuration with downloads disabled.

- [ ] **Step 1: Add OnePacerr options, service user, and Drlight wiring**

Add options for enablement, auto-start, verified Jellyfin library root/name, and the corresponding container path. Create an unprivileged `onepacerr` system user with UID `1500` and the existing `users` group; use the group GID from Nix rather than hardcoding it in the module. Import the module only for Drlight, but leave `enable=false` and `autoStart=false` until the Jellyfin credentials and library preflight pass. Do not add it to Zero or shared media-center targets. Recheck UID `1500` is unused during the pre-deployment host preflight.

- [ ] **Step 2: Render Jellyfin credentials at runtime**

Reuse the existing unqualified `Jellyfin/username` and `Jellyfin/password` Opnix references. When auto-start is approved, extend their dependent-service lists with `podman-onepacerr` so rotations restart the container; do not add a restart dependency for the disabled preflight configuration. Require `jellyfin-admin-auth.service` before starting the container. Add the renderer as an `ExecStartPre` for `podman-onepacerr.service`; it writes `/run/onepacerr/credentials.env` atomically with mode `0600` from the existing secret files. Point the OCI `environmentFiles` option there. Do not interpolate secret values into Nix or log them.

- [ ] **Step 3: Configure the OnePacerr container**

Set `virtualisation.oci-containers.containers.onepacerr` to image `ghcr.io/eltharynd/onepacerr:v1.8.16`, Podman bridge networking, container user `1500:${toString config.users.groups.users.gid}`, a single writable bind mount for the verified library subtree, the runtime environment file, and the required OnePacerr/Jellyfin settings. Use `http://host.containers.internal:8096` for Jellyfin, `LIBRARY_CREATE_SHOW_IF_NOT_FOUND=false`, `PIPELINE_SKIP_DOWNLOADS=true`, and the user-approved existing-file organize/metadata flags. Do not set torrent-client variables or publish ports.

- [ ] **Step 4: Run the focused check to verify GREEN**

Run: `nix build .#checks.x86_64-linux.drlight-onepacerr --no-link --impure`.  
Expected: PASS for service enablement, runtime secret handling, container user/network/mounts, disabled downloads, private exposure, and preserved Arr-to-Ultra Transmission settings.

### Task 3: Update OnePacerr and Transmission migration guidance

**Files:**
- Modify: `docs/how-to/migrate-ultra-media-apps-to-drlight.md`
- Modify: `docs/reference/options.md`
- Modify: `docs/plans/2026-10-31-type-observability-media-archetypes.md`
- Modify: `tests/test-zero.nix`

- [ ] **Step 1: Document the OnePacerr library-only phase**

Update the current how-to with the OnePacerr Opnix credential source, private container networking, path mapping, backup/snapshot gate, auto-start behavior, and `PIPELINE_SKIP_DOWNLOADS=true`. Keep live media paths, media names, hostnames, and secret values out of the runbook.

- [ ] **Step 2: Clarify Transmission ownership and superseded decisions**

Update the current migration how-to to say Arr apps continue using Ultra Transmission via RPC and staging. Mark the old OnePacerr prohibition as superseded for Drlight, while leaving completed plans historical. Regenerate the options reference after adding `myConfig.onePacerr`. Remove the unregistered `zeroMediaAutomationTest` and its stale Zero/Nixarr/OnePacerr assertions; Task 1's Drlight evaluation assertions own those checks and prove remote Arr Transmission integrations remain enabled and the existing RPC/staging paths remain unchanged.

- [ ] **Step 3: Run validation and commit**

Run `devenv tasks run check:lint`, the focused OnePacerr check, `devenv tasks run test:build-checks`, and `devenv tasks run test:eval`. Commit with `jj describe -m "feat: add OnePacerr library management"`, then `jj new`.

## Operational handoff (not executed by these plans)

1. Repair the existing Opnix Jellyfin admin credential reference and verify admin authentication read-only. Then verify the target Jellyfin library name, series, exact filesystem path, OnePacerr/Jellyfin compatibility, permissions, and that the target does not conflict with a Sonarr-managed series. Keep discovered path/name out of logs and reports; encode only the required operational path/name in reviewed Nix configuration.
2. Create and verify a restorable snapshot/backup of the affected library subtree before enabling OnePacerr auto-start or running it manually.
3. Confirm the existing Arr-to-Ultra Transmission RPC reconciliation and stage mapping using the current Opnix fields; do not configure OnePacerr's torrent client in this phase.
4. Build and commit the reviewed Nix changes, then run `devenv tasks run machines:plan --input machine=drlight`; inspect the exact plan before a separately approved apply.
5. After apply, verify Jellyfin credentials, OnePacerr path mapping, organizer/metadata results, Prowlarr proxy egress, FlareSolverr, and Arr Transmission tests. Keep the Ultra services and data intact for rollback.
