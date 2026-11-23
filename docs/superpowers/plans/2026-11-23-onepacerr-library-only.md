# OnePacerr Existing-Library Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable OnePacerr on Drlight to organize the existing Jellyfin library and update its metadata while leaving downloads disabled and Transmission on Ultra.

**Architecture:** Run OnePacerr `v1.8.16` on Drlight's existing Podman-backed OCI container system. Give it a narrow writable library mount, reach Jellyfin through Podman's host gateway, and inject the existing Opnix-backed Jellyfin credentials through a restricted runtime environment file. Preserve the existing Arr-to-Ultra Transmission RPC and staging configuration unchanged.

**Tech Stack:** NixOS OCI containers with Podman, OnePacerr `v1.8.16`, Jellyfin, Opnix, Python standard library, Nix runCommand evaluation tests.

**Spec:** `docs/superpowers/specs/2026-11-23-drlight-media-automation-design.md`

**Dependency:** Execute after `docs/superpowers/plans/2026-11-23-local-prowlarr-flaresolverr.md`; both plans update shared Drlight test registration and different sections of the media migration guide.

**Dependency:** Execute after `docs/superpowers/plans/2026-11-23-local-prowlarr-flaresolverr.md`; both plans update separate sections of the migration how-to.

## Global Constraints

- Keep Transmission on Ultra; Radarr/Sonarr/Lidarr continue to manage it through existing Drlight RPC settings and local completed-download staging.
- Set `PIPELINE_SKIP_DOWNLOADS=true`; omit OnePacerr `TORRENT_URL`, `TORRENT_USER`, and `TORRENT_PASSWORD` in this phase.
- Enable existing-file organization and Jellyfin metadata updates, as approved. OnePacerr auto-starts only after the OnePacerr library path and a restorable backup/snapshot are verified.
- Pin OnePacerr to `ghcr.io/eltharynd/onepacerr:v1.8.16`, not `latest`.
- Use Drlight's existing Jellyfin admin username/password from the default `Opnix` vault, delivered only through a runtime env file. Never put values in Nix expressions, OCI environment literals, command lines, logs, tests, or docs.
- Use the existing Podman OCI backend; run OnePacerr with a dedicated numeric user in the shared `users` group, mount only the verified target library subtree, use the bridge host gateway for Jellyfin, and publish no container ports.
- Do not enable OnePacerr torrent submission, remove files/torrents, or alter staging/cleanup behavior in this plan.
- Deployment is through the reviewed Drlight Machines workflow. No service activation or library mutation occurs during code validation.

## Review Focus

- OnePacerr accidentally gets a Transmission URL/credentials despite downloads being disabled — assert all `TORRENT_*` values are absent (Tasks 1–2).
- Jellyfin paths differ from container paths — verify the existing series and exact root before setting the path map (Task 3).
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

Assert Drlight enables OnePacerr, uses the Podman backend and pinned `v1.8.16` image, has `PIPELINE_SKIP_DOWNLOADS=true`, enables existing-file organization and metadata updates, omits all `TORRENT_*` variables, uses a host-gateway Jellyfin URL, mounts only the configured library path, publishes no ports, runs with the configured `onepacerr:users` numeric identity, and orders its container unit after ZFS/Jellyfin/Opnix secret setup. Also assert Arr Transmission settings remain enabled and unchanged.

- [ ] **Step 2: Add runtime env-renderer behavior checks**

Use temporary fake Jellyfin credential files and a temporary output path. Assert the renderer writes exactly `JELLYFIN_USERNAME` and `JELLYFIN_PASSWORD`, preserves supported special characters, creates the output with mode `0600`, rejects multi-line values, and never prints credential contents. Keep fixture values synthetic.

- [ ] **Step 3: Register the check and verify RED**

Register `drlight-onepacerr` in `tests/default.nix`, update the OnePacerr coverage comment in `tests/test-coverage.nix`, and stage the new test path so Nix can read it. Run: `nix build .#checks.x86_64-linux.drlight-onepacerr --no-link --impure`.  
Expected: FAIL because OnePacerr is not imported/enabled on Drlight and the runtime env renderer is absent.

### Task 2: Implement the Drlight OnePacerr service in library-only mode

**Files:**
- Modify: `modules/nixos/onepacerr.nix`
- Create: `modules/nixos/scripts/onepacerr-env.py`
- Modify: `modules/nixos/media-app-reconciliation.nix`
- Modify: `library/machines/catalog.nix`
- Modify: `machines/drlight/default.nix`
- Modify: `tests/test-drlight-onepacerr.nix`

**Interfaces:**
- Consumes: the verified Jellyfin library name/path, existing `/run/secrets/jellyfin-admin-username` and `jellyfin-admin-password`, and the OCI unit `podman-onepacerr.service`.
- Produces: `myConfig.onePacerr.enable`, explicit host/container library-path options, an Opnix-backed runtime env file, and an auto-starting OnePacerr container with downloads disabled.

- [ ] **Step 1: Add OnePacerr options, service user, and Drlight wiring**

Add options for enablement, verified Jellyfin library root/name, and the corresponding container path. Create an unprivileged `onepacerr` system user in the existing `users` group. Import the module only for Drlight and enable it in `machines/drlight/default.nix`; do not add it to Zero or shared media-center targets.

- [ ] **Step 2: Render Jellyfin credentials at runtime**

Reuse the existing unqualified `Jellyfin/username` and `Jellyfin/password` Opnix references. Extend their dependent-service lists with the env renderer and `podman-onepacerr` so rotations refresh the runtime env file and container. Generate `/run/onepacerr/credentials.env` atomically with mode `0600` from the existing secret files; do not interpolate secret values into Nix. Make `podman-onepacerr.service` require/order after the env renderer, Opnix, ZFS mount, and Jellyfin services. Ensure no values are logged.

- [ ] **Step 3: Configure the OnePacerr container**

Set `virtualisation.oci-containers.containers.onepacerr` to image `ghcr.io/eltharynd/onepacerr:v1.8.16`, Podman bridge networking, container user `onepacerr:<users-gid>`, a single writable bind mount for the verified library subtree, the runtime environment file, and the required OnePacerr/Jellyfin settings. Use `http://host.containers.internal:8096` for Jellyfin, `LIBRARY_CREATE_SHOW_IF_NOT_FOUND=false`, `PIPELINE_SKIP_DOWNLOADS=true`, and the user-approved existing-file organize/metadata flags. Do not set torrent-client variables or publish ports.

- [ ] **Step 4: Run the focused check to verify GREEN**

Run: `nix build .#checks.x86_64-linux.drlight-onepacerr --no-link --impure`.  
Expected: PASS for service enablement, runtime secret handling, container user/network/mounts, disabled downloads, private exposure, and preserved Arr-to-Ultra Transmission settings.

### Task 3: Update OnePacerr and Transmission migration guidance

**Files:**
- Modify: `docs/how-to/migrate-ultra-media-apps-to-drlight.md`
- Modify: `docs/plans/2026-10-31-type-observability-media-archetypes.md`
- Modify: `tests/test-zero.nix`

- [ ] **Step 1: Document the OnePacerr library-only phase**

Update the current how-to with the OnePacerr Opnix credential source, private container networking, path mapping, backup/snapshot gate, auto-start behavior, and `PIPELINE_SKIP_DOWNLOADS=true`. Keep live media paths, media names, hostnames, and secret values out of the runbook.

- [ ] **Step 2: Clarify Transmission ownership and superseded decisions**

Update the current migration how-to to say Arr apps continue using Ultra Transmission via RPC and staging. Mark the old OnePacerr prohibition as superseded for Drlight, while leaving completed plans historical. Remove the unregistered `zeroMediaAutomationTest` and its stale Zero/Nixarr/OnePacerr assertions; Task 1's Drlight evaluation assertions own those checks and prove remote Arr Transmission integrations remain enabled with unchanged Opnix references/mappings.

- [ ] **Step 3: Run validation and commit**

Run `devenv tasks run check:lint`, the focused OnePacerr check, `devenv tasks run test:build-checks`, and `devenv tasks run test:eval`. Commit with `jj describe -m "feat: add OnePacerr library management"`, then `jj new`.

## Operational handoff (not executed by these plans)

1. Read-only verify Jellyfin's existing target series/library root and OnePacerr/Jellyfin compatibility. Keep the discovered path/name out of Git, logs, and reports.
2. Create and verify a restorable snapshot/backup of the affected library subtree before any OnePacerr organization/metadata run.
3. Confirm the existing Arr-to-Ultra Transmission RPC reconciliation and stage mapping using the current Opnix fields; do not configure OnePacerr's torrent client in this phase.
4. Build and commit the reviewed Nix changes, then run `devenv tasks run machines:plan --input machine=drlight`; inspect the exact plan before a separately approved apply.
5. After apply, verify Jellyfin credentials, OnePacerr path mapping, organizer/metadata results, Prowlarr proxy egress, FlareSolverr, and Arr Transmission tests. Keep the Ultra services and data intact for rollback.
