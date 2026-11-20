# Drlight Tailscale Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Drlight the only Tailscale-enabled machine and make every Drlight service currently restricted to `tailscale0` reachable through the home LAN interface `eno1` as well.

**Architecture:** Keep Tailscale policy and existing `tailscale0` firewall rules intact. Add a Drlight-specific LAN firewall policy on `eno1`, derive its ports from the enabled service configuration, and update Drlight dnsmasq to listen on both interfaces. Remove non-Drlight enablement and obsolete Tailscale Serve configuration from the catalog.

**Tech Stack:** NixOS modules, nix-darwin/NixOS machine catalog, Nix evaluation tests, devenv tasks.

**Spec:** `docs/superpowers/specs/2026-11-20-drlight-tailscale-gateway-design.md`

## Global Constraints

- Disable Tailscale on every catalog machine except Drlight.
- Preserve Drlight’s Tailscale tags and existing tailnet service behavior.
- Expose Drlight’s Tailscale-only service ports on `eno1` only; do not open them globally.
- Do not turn Drlight into a general-purpose subnet router.
- Do not deploy or authenticate any live machine.
- Use English documentation and conventional commit messages.

## Review Focus

- A newly enabled Tailscale service on Drlight must not silently remain LAN-inaccessible; test LAN policy derives from configured service ports.
- LAN exposure must not become global exposure; test the ports remain absent from `networking.firewall.allowedTCPPorts`.
- DNS must remain reachable on both interfaces and retain existing split-DNS records; test both interface membership and records.
- Non-Drlight machines must not retain Tailscale enablement or Serve mappings; test the full catalog boundary.
- Node exporter uses an interface list while other services use Tailscale opt-ins; test both paths independently.

---

### Task 1: Add failing gateway-policy tests

**Files:**
- Modify: `tests/test-media-center-archetype.nix`
- Modify: `tests/test-tailscale-config.nix`
- Modify: `tests/default.nix` only if a new test derivation is needed

**Interfaces:**
- Consumes: resolved `self.nixosConfigurations.drlight.config`, `catalog`, and existing test helpers.
- Produces: assertions for Drlight LAN exposure, dual-interface DNS, and catalog-wide Tailscale enablement.

- [ ] **Step 1: Write the failing Drlight LAN assertions**

  Assert that `eno1` contains the enabled media-manager ports, Prometheus/Loki ports when their Tailscale firewall options are enabled, node-exporter port, and DNS port; assert those ports are not globally opened. Assert dnsmasq interfaces contain both `eno1` and `tailscale0`.

- [ ] **Step 2: Write the failing catalog assertions**

  Assert Drlight is enabled with `['tag:home-lab' 'tag:media-center']`, every other catalog machine resolves with `myConfig.tailscale.enable == false`, and no non-Drlight machine retains a `tailscale.serve` mapping.

- [ ] **Step 3: Run focused checks and confirm failure**

  Run `devenv tasks run test:build-checks`.
  Expected: the new assertions fail because non-Drlight machines are still enabled, dnsmasq remains Tailscale-only, and no Drlight LAN policy exists.

### Task 2: Make Drlight services reachable on the LAN

**Files:**
- Modify: `machines/drlight/default.nix`
- Modify: `modules/nixos/tailscale-home-dns.nix`
- Modify: `modules/nixos/prometheus.nix` only if the existing interface option cannot express Drlight’s LAN requirement
- Modify: `modules/nixos/media-management.nix` only if its firewall rule needs a shared interface option

**Interfaces:**
- Consumes: existing configured service ports and Drlight’s `eno1` LAN identity.
- Produces: explicit `eno1` firewall allowances for the same services currently reachable via `tailscale0`; dnsmasq listens on `eno1` and `tailscale0`.

- [ ] **Step 1: Add the minimal Drlight LAN firewall policy**

  In Drlight’s machine-specific configuration, add `eno1` TCP/UDP rules for the resolved ports currently exposed through Drlight’s Tailscale-only paths: media managers, Prometheus, Loki, node exporter, and DNS. Reuse service option values rather than duplicating literal ports where possible. Keep global firewall port lists unchanged.

- [ ] **Step 2: Update home DNS interface binding**

  Change `modules/nixos/tailscale-home-dns.nix` so dnsmasq binds to `['eno1' 'tailscale0']` and retains its existing Tailscale firewall rules and split-DNS records.

- [ ] **Step 3: Configure node exporter’s LAN interface explicitly**

  Set Drlight’s `nodeExporter.openFirewallInterfaces` to `['tailscale0' 'eno1']` while leaving the shared default Tailscale-only behavior unchanged for other machines.

- [ ] **Step 4: Run focused tests and confirm they pass**

  Run `devenv tasks run test:build-checks`.
  Expected: Drlight LAN and DNS assertions pass; catalog assertions remain red until Task 3.

### Task 3: Remove Tailscale from all other machines

**Files:**
- Modify: `library/machines/catalog.nix`
- Modify: relevant existing tests whose expected enabled-machine set changes

**Interfaces:**
- Consumes: the catalog’s `overrides.tailscale` policy and Drlight gateway policy from Task 2.
- Produces: only Drlight has `myConfig.tailscale.enable = true`; non-Drlight machines have no active Tailscale service or Serve mapping.

- [ ] **Step 1: Set non-Drlight catalog overrides to disabled**

  Set `tailscale.enable = false` for `type-nas`, `type-server`, `zero`, and `MegamanX`; remove MegamanX’s Bifrost Serve mapping and any other Tailscale-only per-machine settings that are no longer valid. Leave already-disabled machines unchanged.

- [ ] **Step 2: Update expectations for the new gateway boundary**

  Adjust tests that currently require MegamanX, Zero, or other machines to run Tailscale. Preserve tests of the shared Tailscale module itself using synthetic enabled configurations where they are testing module behavior rather than machine policy.

- [ ] **Step 3: Run focused tests**

  Run `devenv tasks run test:build-checks`.
  Expected: all gateway and catalog assertions pass.

### Task 4: Format, validate, and commit

**Files:**
- Modify: any files identified by lint or test diagnostics only.

- [ ] **Step 1: Format and lint**

  Run `devenv tasks run check:lint` and fix Alejandra/statix findings without broad unrelated cleanup.

- [ ] **Step 2: Run the full required validation**

  Run `devenv tasks run test:all`.
  Expected: evaluation, package, and build-check suites pass.

- [ ] **Step 3: Review the final diff**

  Confirm only the approved design, catalog, Drlight LAN policy, DNS binding, and relevant tests changed; confirm no deployment or live authentication command was run.

- [ ] **Step 4: Describe and advance the JJ change**

  Run `jj describe -m "feat: make drlight the tailscale gateway"`, then `jj new`.
