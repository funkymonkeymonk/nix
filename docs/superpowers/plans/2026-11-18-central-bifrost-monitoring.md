# Central Bifrost Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade MegamanX to tagged OSS Bifrost HTTP 2.5.1 and scrape its tailnet-private `/metrics` endpoint from drlight Prometheus without altering the existing SQLite-backed provider configuration.

**Architecture:** Pin the `bifrost` source input to upstream's `transports/v2.5.1` tag and adapt the local Nix overlay's package version and hashes as needed. Keep Bifrost loopback-only and its existing SQLite provider data unchanged. Metrics whitelisting, tailnet-only publishing, and the drlight Prometheus scrape remain blocked until Bifrost's DB-backed configuration can safely persist the whitelist and remote metrics path is verified.

**Tech Stack:** Nix flake input/overlay, nix-darwin launchd, NixOS Prometheus, Tailscale Serve, Nix evaluation tests, Devenv task checks.

**Spec:** `docs/superpowers/specs/2026-11-18-central-bifrost-monitoring-design.md`

## Global Constraints

- Upgrade to tagged OSS transport `v2.5.1`; do not use untagged `main`.
- Keep Bifrost listener on `127.0.0.1:8081`; do not expose its UI or inference APIs over the network.
- Keep current SQLite providers, keys, and model configuration unchanged.
- Add only exact `/metrics` to the unauthenticated route whitelist; do not use prefix wildcards, once safely persisted.
- Reachability of `/metrics` must be restricted to the Tailscale interface/network; do not enable the scrape before remote verification.
- User's existing edits in `machines/wweaver/default.nix`, `modules/home-manager/pi-coding-agent.nix`, `tests/test-coverage.nix`, and `tests/test-lydia-migration.nix` must be preserved.
- Do not deploy without a committed tree, a reviewed `machines:plan` result, and the returned plan ID.

## Review Focus

- **Version consistency:** package metadata/binary must report HTTP 2.5.1 and source must be the tagged upstream release. Test package version and verify built binary version.
- **Nix patch compatibility:** UI dependency hash, Go vendor hash, and local module replacements may have changed. Build the Darwin Bifrost package and verify the resulting executable before proceeding.
- **Database preservation:** Bifrost's config database contains working providers and keys. Never replace the DB or reconcile the provider list as part of metrics setup; test the upgrade on a backup/copy if configuration migration is required.
- **Metrics route behavior:** exact whitelist should allow `/metrics` but not broaden management route access. Verify local and tailnet responses and confirm the exposition content type/body.
- **Network exposure:** verify Bifrost still binds loopback, and that the dedicated metrics publication cannot proxy `/`, `/api/*`, or `/v1/*`.

---

## File Structure

- `flake.nix` / `flake.lock`: pin upstream source to `transports/v2.5.1`.
- `overlays/default.nix`: set Bifrost HTTP/UI package metadata and compatible dependency hashes.
- Package update files: pin tagged source and compatible version/hash metadata.
- `modules/services/bifrost/darwin.nix`: any future whitelist mechanism must preserve the current database-backed provider/key state.
- Tailnet routing and Prometheus target files remain unchanged until Bifrost `/metrics` is verified locally and remotely.
- `tests/test-bifrost.nix`, observability tests, and Tailscale tests: lock down version/config, route restriction, and scrape output.

## Task 1: Pin and build Bifrost HTTP 2.5.1

**Files:**
- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `overlays/default.nix`
- Test: `tests/test-bifrost.nix` (or package-specific test in `tests/default.nix`)

- [ ] Write a test asserting the selected package metadata/version is 2.5.1 and package override targets the intended Bifrost package.
- [ ] Run the focused test and verify it fails because the package remains 1.4.9.
- [ ] Pin input to the exact upstream `transports/v2.5.1` tag and update lock.
- [ ] Update package version and dependency hashes based on source from that tag; retain local Nix compatibility patches only when still required.
- [ ] Build `.#darwinConfigurations.MegamanX.pkgs.bifrost-http` (or the equivalent package derivation) and verify the binary reports 2.5.1.
- [ ] Run the focused Bifrost tests and lint.

## Task 2: Add persistent metrics whitelist without DB/provider replacement (blocked; do not implement until storage behavior is verified)

**Files:**
- Modify: `modules/services/bifrost/darwin.nix`
- Modify: `tests/test-bifrost.nix`

- [ ] Write a test asserting generated config has `client.whitelisted_routes = ["/metrics"]` and preserves the configured provider set.
- [ ] Run the focused test and verify it fails because only `providers` are currently emitted.
- [ ] Implement the narrow whitelist and establish how the supported v2.5.1 file/DB reconciliation semantics preserve existing providers/keys. Consult pinned v2.5.1 docs/source.
- [ ] If declarative seeding cannot safely preserve current DB state, do not implement an automatic migration; instead create a documented/manual Bifrost UI/API step for adding only this client setting and keep Nix from overwriting database state.
- [ ] Verify tests pass and no admin/setup credentials or provider key values are added to Nix store output.

## Task 3: Publish only metrics over Tailscale (blocked pending Task 2)

**Files:**
- Modify: `modules/services/tailscale/darwin.nix` or create focused `modules/services/bifrost/metrics-proxy-darwin.nix`
- Modify: `library/machines/catalog.nix`
- Test: focused Tailscale/Bifrost tests

- [ ] Add a test for path behavior ensuring an external `/metrics` request maps to upstream `127.0.0.1:8081/metrics`, while `/`, `/api/config`, and `/v1/models` are not forwarded.
- [ ] Run test and confirm failure before implementation.
- [ ] Probe installed `tailscale serve` path semantics; use existing Serve only if the requested path is preserved and other gateway routes are not published. Otherwise add a minimal reverse proxy that binds specifically to the resolved Tailscale IPv4 address and only serves exact GET `/metrics` to the loopback Bifrost endpoint.
- [ ] Configure MegamanX only; no Tailscale exposure changes on other machines.
- [ ] Test generated launchd arguments, listener binding, readiness/restart behavior, and non-matching paths.

## Task 4: Configure drlight Prometheus scrape target (blocked pending verified endpoint)

**Files:**
- Modify: `modules/nixos/prometheus.nix`
- Modify: `library/archetypes/type-observability.nix` or central machine metadata wiring
- Test: `tests/test-nixos-observability.nix`

- [ ] Write a test asserting central Prometheus scrape config includes exactly one `bifrost` job targeting the verified MegamanX tailnet metrics endpoint with label `host="MegamanX"`, while standalone Prometheus configs remain unchanged.
- [ ] Run the focused test and confirm failure before implementation.
- [ ] Implement a narrowly gated scrape option/target based on current catalog conventions; avoid adding Bifrost scrape to non-observability hosts.
- [ ] Verify rendered Prometheus configuration and focused test results.

## Task 5: Integration verification and deployment readiness

**Files:**
- Modify docs/design as necessary for final verified behavior.

- [ ] Run `devenv tasks run check:lint`.
- [ ] Run focused tests: Bifrost, Tailscale route, observability inventory, NixOS observability, and build checks.
- [ ] Build the MegamanX Bifrost package/system without deploying.
- [ ] Review diff and confirm user changes are unchanged.
- [ ] After code is committed, run `devenv tasks run machines:plan --input machine=MegamanX`; review exact target and planned package/service/database impacts. Stop if provider database changes or unrelated broad changes appear.
- [ ] Apply only after explicit plan review/approval, using the returned plan ID and `devenv tasks run machines:apply --input machine=MegamanX --input planId=<plan-id>`.
- [ ] Verify running Bifrost version `2.5.1`, `/v1/models` returns the configured model, local `/metrics` returns exposition, tailnet remote `/metrics` works, non-metrics paths are not exposed via the metrics listener, drlight Prometheus target is up, and Vector logs continue reaching Loki.

## Notes

The owner requested the Bifrost upgrade and setup. The Bifrost package update can be completed and built independently. Metrics setup is blocked until the exact v2.5.1 config-store reconciliation behavior is verified and a tailnet-only `/metrics` route is proven end-to-end. Existing deployment uses the prescribed Machines review-first flow; do not use direct SSH activation or `system:switch` for remote MegamanX.