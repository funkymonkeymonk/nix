# Shared Nixpkgs Update and Prowlarr Restore Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the shared Nixpkgs lock so Drlight's Prowlarr package is compatible with the seedbox backup from version `3.0.2.5780`, then prepare and execute only the reviewed Drlight deployment and restore.

**Architecture:** Advance the existing shared `nixpkgs` flake input rather than adding a Prowlarr-only package source. Add an evaluation assertion for the required Prowlarr version, run the full repository checks against the new package set, deploy Drlight through a new single-machine Machines plan, and restore the supplied native backup only after the deployed version and active-sync gate are confirmed.

**Tech Stack:** Nix Flakes / shared Nixpkgs, NixOS Prowlarr and FlareSolverr services, native Prowlarr backup/restore, Jujutsu, Devenv Machines.

**Spec:** `docs/superpowers/specs/2026-11-23-drlight-media-automation-design.md`

## Global Constraints

- Use the shared `nixpkgs` input; do not add a package-scoped Nixpkgs pin or Prowlarr override.
- The deployed Prowlarr package must be `3.0.2.5780` or newer before restoring the seedbox backup from `3.0.2.5780`.
- The shared input affects package evaluation for all configured systems; validate all NixOS/Darwin evaluations, but deploy only Drlight.
- Keep the supplied backup outside Git and the Nix store; restrict its local permissions before handling it and never print archive contents or secret-bearing configuration to logs.
- Keep Ultra Prowlarr/FlareSolverr and their state intact. Ensure only one Prowlarr instance actively syncs Arr apps during restore and cutover.
- Keep OnePacerr disabled; its separate Jellyfin admin-auth and library-path preflight has not passed.
- Use `machines:plan` and apply only the exact reviewed plan ID for `drlight`. Do not deploy other machines or pass a non-interactive confirmation flag.

## Review Focus

- The updated shared Nixpkgs package does not meet the source-version floor or introduces NixOS module incompatibilities — assert the version and run full evaluation/build checks (Tasks 1–3).
- The shared input update changes unrelated systems or yields an unexpectedly broad Drlight plan — review the lock diff and single-machine plan before apply (Tasks 2–4).
- The supplied archive is corrupt or restored into an older Prowlarr binary — verify archive integrity and deployed version before restore (Tasks 4–5).
- Ultra and Drlight Prowlarr both sync Arr apps — disable Ultra's Arr app integrations before restoring/enabling local app sync (Task 5).
- Backup credentials leak into the repository, Nix store, command output, or logs — keep the archive local and use the native restore UI (Task 5).

---

### Task 1: Add a failing Drlight Prowlarr version-floor assertion

**Files:**
- Modify: `tests/test-drlight-media-indexers.nix`

**Interfaces:**
- Consumes: `self.nixosConfigurations.drlight.config.services.prowlarr.package.version`.
- Produces: An evaluation assertion that Drlight's Prowlarr package is at least `3.0.2.5780`.

- [ ] **Step 1: Add the version-floor assertion**

Assert `lib.versionAtLeast prowlarr.package.version "3.0.2.5780"` in the existing Drlight media-indexer test.

- [ ] **Step 2: Confirm RED**

Run `nix build .#checks.x86_64-linux.drlight-media-indexers --no-link --impure`. It must fail specifically because the pinned package is `2.6.5.5623`.

### Task 2: Advance the shared Nixpkgs input

**Files:**
- Modify: `flake.lock`

- [ ] **Step 1: Update only the shared Nixpkgs input**

Run `nix flake update nixpkgs`. Review the lockfile diff and confirm the intended shared input moved; do not update unrelated inputs unless Nix reports a required follow edge.

- [ ] **Step 2: Check the evaluated Drlight package version**

Run `nix eval --raw .#nixosConfigurations.drlight.config.services.prowlarr.package.version`. Confirm it is `3.0.2.5780` or newer, then rerun the focused Drlight media-indexer check to verify GREEN.

### Task 3: Validate the full repository against the new package set

**Files:**
- No additional production files; the version assertion remains in `tests/test-drlight-media-indexers.nix`.

- [ ] **Step 1: Commit the lock/test change before final Nix validation**

Use a conventional Jujutsu description such as `chore: update shared nixpkgs input` so the flake evaluates the committed lock.

- [ ] **Step 2: Run the required checks**

Run `devenv tasks run check:lint` and `devenv tasks run test:all`. Confirm the evaluated Drlight Prowlarr version remains at least `3.0.2.5780`.

### Task 4: Generate and review a Drlight-only deployment plan

**Files:**
- No repository files; use the existing ignored `devenv.local.nix` target entry.

- [ ] **Step 1: Generate the plan for exactly Drlight**

Run `devenv tasks run machines:plan --input machine=drlight`. Record the emitted plan ID and inspect `.devenv/machine-plans/<plan-id>/plan.json`.

- [ ] **Step 2: Review the exact target and proposed changes**

Confirm the plan contains exactly one machine (`drlight`) at the configured target, Prowlarr `3.0.2.5780` or newer, FlareSolverr, private firewall rules, and no OnePacerr service. Review the Drlight package/system changes expected from the shared Nixpkgs update. Stop if other machines, unexpected service/data changes, target mismatch, or unresolved plan findings appear.

- [ ] **Step 3: Apply only the reviewed plan and verify Drlight**

After the plan is reviewed, apply using its exact plan ID with `devenv tasks run machines:apply --input machine=drlight --input planId=<reviewed-plan-id>`, then run `devenv tasks run machines:check --input machine=drlight`. Verify remotely that Prowlarr and FlareSolverr are active and the installed Prowlarr version is at least `3.0.2.5780`.

### Task 5: Validate and restore the supplied native Prowlarr backup

**Files:**
- No repository files; the archive remains local and is not copied into the Nix store or Git.

- [ ] **Step 1: Secure and validate the local archive**

Restrict the supplied backup file to owner-only permissions and run an integrity check without printing archive contents. Stop if it is unreadable or corrupt.

- [ ] **Step 2: Enforce a single active Arr syncer**

Preserve the original Ultra backup, disable Ultra Prowlarr's Arr app integrations, and create a migration backup with app sync disabled. Keep Ultra Prowlarr available for rollback.

- [ ] **Step 3: Restore through Prowlarr's native UI**

Access Drlight Prowlarr over its private LAN/Tailscale address, restore the migration backup through **System → Backups → Restore**, and allow Prowlarr to restart. Do not pass archive contents or credentials through shell arguments or logs.

- [ ] **Step 4: Configure and verify local runtime integrations**

Configure Prowlarr's General Proxy from the `Ultra.cc HTTP Proxy` Opnix item, enable local-address bypass, set Sonarr/Radarr to their loopback URLs, and set FlareSolverr to `127.0.0.1:8191`. Test connections and Ultra egress before enabling Drlight Arr app sync. Keep Ultra services and backups for rollback.

## Operational boundary

OnePacerr is not part of this update/restore plan. Do not enable or start it until Jellyfin admin authentication, the exact library identity/path, permissions, and a restorable media snapshot pass the separate OnePacerr preflight.
