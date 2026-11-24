# Local Prowlarr and FlareSolverr Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Prowlarr and FlareSolverr on Drlight, connect them to the local Arr apps, and route indexer egress through Ultra's public HTTP proxy.

**Architecture:** Add a Drlight-only NixOS module for Prowlarr and FlareSolverr, keeping Prowlarr available on the existing private interfaces and FlareSolverr internal. Restore Prowlarr's existing application state, then configure the proxy and local app URLs in Prowlarr's runtime settings.

**Tech Stack:** NixOS pinned nixpkgs, Prowlarr 2.6.5.5623, FlareSolverr 3.5.2, Ultra HTTP proxy, Opnix, Nix runCommand evaluation tests.

**Spec:** `docs/superpowers/specs/2026-11-23-drlight-media-automation-design.md`

## Global Constraints

- Configure Prowlarr's General HTTP Proxy with Ultra's UCP host, port `8080`, service username, and dedicated proxy password from the `Ultra.cc HTTP Proxy` item in Drlight's default `Opnix` vault.
- Ultra proxy authentication is HTTP Basic over public HTTP; the user accepts that transport risk. Never put proxy credentials or live endpoints in Nix literals, command lines, logs, tests, or docs.
- Keep Prowlarr available only on Drlight's home-LAN and Tailscale interfaces; do not add a global firewall opening or public Caddy route.
- Keep FlareSolverr on loopback/internal access only; do not publish its port.
- Prowlarr local API calls to Sonarr/Radarr and FlareSolverr must bypass the external proxy.
- Keep Ultra Prowlarr/FlareSolverr and their source data intact until local state, indexers, proxy egress, FlareSolverr, and Arr sync are verified. Do not deploy or cut over without a reviewed Drlight Machines plan.
- Keep Transmission on Ultra; do not alter RPC, staging, seeding, or cleanup behavior in this plan.

## Review Focus

- Source Prowlarr version/backup compatibility — stop before restore if it would downgrade or require unsupported conversion (Task 3).
- Local app URLs accidentally routed through the proxy — assert local bypass and loopback endpoints (Tasks 1–2).
- Accidental public exposure of Prowlarr or FlareSolverr — assert interface-specific firewall rules and no Caddy route (Task 1).
- FlareSolverr challenge requests bypassing Ultra egress — verify the pinned Prowlarr integration forwards the General Proxy settings (Task 3).
- Both Ultra and Drlight Prowlarr instances syncing the same Arr apps at once — document a single-active-sync cutover (Task 3).

---

### Task 1: Add failing Drlight media-indexer evaluation tests

**Files:**
- Create: `tests/test-drlight-media-indexers.nix`
- Modify: `tests/default.nix`
- Modify: `tests/test-coverage.nix`

**Interfaces:**
- Consumes: `self.nixosConfigurations.drlight.config` and the existing `checkTrue`, `checkFalse`, and `checkEqual` test style in `tests/test-media-center-archetype.nix`.
- Produces: `drlightMediaIndexersTest`, registered as `checks.x86_64-linux.drlight-media-indexers`.

- [ ] **Step 1: Write the failing test**

Assert that Drlight enables Prowlarr and FlareSolverr; Prowlarr uses port `9696`, Forms authentication, external updates, and `openFirewall = false`; FlareSolverr uses port `8191` with `openFirewall = false`; only Prowlarr's UI port is allowed on `eno1` and `tailscale0`; and neither service is exposed through global `allowedTCPPorts` or Caddy.

- [ ] **Step 2: Register the check and make the new file visible to Nix**

Add the import/registration in `tests/default.nix`, add `nixos/media-indexers.nix` to `tests/test-coverage.nix`, and stage the new test file before evaluating the uncommitted tree.

- [ ] **Step 3: Run the focused test to confirm RED**

Run: `nix build .#checks.x86_64-linux.drlight-media-indexers --no-link --impure`  
Expected: FAIL because Drlight has no configured Prowlarr/FlareSolverr services or private firewall assertions yet.

### Task 2: Add Drlight-local Prowlarr and FlareSolverr services

**Files:**
- Create: `modules/nixos/media-indexers.nix`
- Modify: `library/machines/catalog.nix`
- Modify: `tests/test-drlight-media-indexers.nix`

**Interfaces:**
- Consumes: the Drlight machine module list and pinned nixpkgs `services.prowlarr`/`services.flaresolverr` options.
- Produces: Drlight-only Prowlarr and FlareSolverr configuration plus private Prowlarr UI port rules.

- [ ] **Step 1: Import the new module only into Drlight**

Add `../../modules/nixos/media-indexers.nix` to the Drlight module list in `library/machines/catalog.nix`; do not add it to shared media-center archetypes or other machines.

- [ ] **Step 2: Implement the services in `modules/nixos/media-indexers.nix`**

Enable Prowlarr and FlareSolverr using pinned nixpkgs packages. Set Prowlarr port `9696`, bind address `*`, Forms authentication required, URL base empty, and update mechanism external. Keep `openFirewall = false` for both. Allow Prowlarr's port only on Drlight's existing private `eno1` and `tailscale0` interfaces; do not add FlareSolverr port `8191` to any firewall interface. Do not define proxy credentials, URLs, or indexer data in Nix.

- [ ] **Step 3: Run the focused test to confirm GREEN**

Run: `nix build .#checks.x86_64-linux.drlight-media-indexers --no-link --impure`  
Expected: PASS, including private-interface firewall assertions.

### Task 3: Document Prowlarr backup, restore, proxy, and cutover steps

**Files:**
- Modify: `docs/how-to/migrate-ultra-media-apps-to-drlight.md`
- Modify: `docs/adr/0003-declarative-media-app-reconciliation.md`
- Modify: `docs/explanation/api-reconciliation.md`
- Modify: `docs/plans/2026-11-09-ultra-media-retention.md`
- Create: `docs/adr/0004-drlight-local-indexer-egress.md`

- [ ] **Step 1: Update the current how-to and architecture decision**

Replace instructions that keep Prowlarr/FlareSolverr on Ultra with Drlight-local Prowlarr/FlareSolverr, private local Arr URLs, and Ultra public-proxy setup. State the Basic-auth HTTP transport risk without including proxy values. Mark the old Prowlarr-location decision superseded and link the new ADR.

- [ ] **Step 2: Document backup and rollback**

Require a version-checked Prowlarr-native backup outside Git, keep Ultra services/state for rollback, and ensure only one Prowlarr instance actively syncs Arr apps at cutover. Do not document live hostnames, IPs, media paths, or credentials.

- [ ] **Step 3: Run focused validation and commit**

Run `devenv tasks run check:lint`, the focused Nix check, and `devenv tasks run test:build-checks`. Commit with `jj describe -m "feat: add local media indexer services"` and leave a fresh change with `jj new`.

## Operational handoff (not executed by this plan)

1. Verify Ultra Prowlarr/FlareSolverr source versions and create a protected Prowlarr backup.
2. Apply Drlight only through `machines:plan` and a separately approved `machines:apply`.
3. Restore Prowlarr, configure its General Proxy from the Opnix item, enable local-address bypass, and set FlareSolverr to `127.0.0.1:8191`. In Prowlarr **Settings → Apps**, use Prowlarr `127.0.0.1:9696`, Sonarr `127.0.0.1:8989`, and Radarr `127.0.0.1:7878`, with each Arr API key.
4. Test proxy egress and a representative indexer; verify an indexer's observed egress is Ultra. Keep Ultra source state until all tests pass.
