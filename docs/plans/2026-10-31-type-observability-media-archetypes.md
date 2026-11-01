# Server, Media-Center, and Observability Archetypes Implementation Plan

> **Note:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Refactor the machine profiles into reusable server, media-center, and observability archetypes, centralize telemetry on drlight, and retire Darwin Grafana and inactive local seed-box configuration.

**Architecture:** The machine catalog remains authoritative for host composition and exporter endpoints. `type-server` supplies server collectors, `type-media-center` imports it, and `type-observability` separately supplies Prometheus/Loki/Alertmanager/Grafana on drlight. Prometheus target records are generated from catalog node-exporter metadata, while Vector's storage host remains configurable and defaults to localhost.

**Tech Stack:** NixOS/nix-darwin modules, Nix flake-parts machine catalog, opnix, Prometheus file/config generation, Nix runCommand evaluation tests, devenv checks, jj workspaces and stacked PRs.

---

## Source of truth and global constraints

- Binding design: `docs/superpowers/specs/2026-10-31-type-observability-media-archetypes-design.md`.
- Preserve machine outputs `type-server-arm`, `type-nas`, and `drlight`; do not rename hosts.
- Catalog exporter metadata is the single source for both node-exporter enablement and Prometheus target generation. Do not derive one machine's Nix configuration by evaluating another machine's `self.*Configurations` output.
- Default scrape address is the catalog hostname. An optional address field overrides it with a hostname or IP. Default node-exporter port is 9100; use a machine's configured port if overridden.
- Runtime targets include every configured exporter across NixOS and Darwin, even when offline. Prometheus reports availability; no runtime Tailscale API query or target scanner is added.
- Restrict exporter reachability to configured interfaces. Tailscale is the normal route; other routed networks require an explicit per-host address/access setting. Never open node_exporter broadly by default. Until access is configured, type-server-arm (Tailscale disabled) and Darwin exporters remain inaccessible remotely but stay in Prometheus inventory as unavailable targets.
- Vector's destination host defaults to `localhost`. Collector-only hosts use drlight's configured reachable hostname/address; drlight uses the default.
- Drlight remains the only host in this scope with Prometheus, Loki, Alertmanager, and Grafana. `type-nas` retains node_exporter but loses local Prometheus. Darwin targets retain configured collectors but lose local Prometheus/Loki/Alertmanager/Grafana.
- Grafana credentials use opnix references `Grafana - Home/username` and `Grafana - Home/password` under drlight's existing Homelab default vault. Do not hard-code the `op://Homelab/` prefix, resolve secret values, or place values in the Nix store.
- Drlight keeps local Jellyfin and its ZFS media storage. Remove active Caddy/Homepage entries for remote seed-box services and stale Sunshine. Remove the backup job and `/var/lib/nixarr` secret/path. Do not enable OnePacerr or seed-box applications locally.
- Tests are written before implementation. Each test must be observed failing before its corresponding implementation is written. No live switch or deployment.
- Each PR is based on the previous PR in the stack and has a focused, passing test set. Push/create PRs only after its implementation and validation are ready; never rewrite a pushed commit.

## PR 1 — Extract the reusable `type-server` archetype and collector profile

### Task 1: Specify collector/archetype behavior in failing tests

**Files:**
- Create or extend: `tests/test-server-archetypes.nix`
- Modify: `tests/default.nix`
- Modify as needed: `tests/test-nixos-observability.nix`

**Step 1: Write the failing tests**

Cover the evaluated configurations for `type-server` and `type-server-arm`:

- Both select the shared server archetype and enable Vector plus node_exporter.
- Their machine identity, target module, and disk/hardware modules remain present.

Prefer behavior assertions against evaluated NixOS configurations. If full target evaluation is unavailable from a test helper, keep the existing test helper pattern and assert the generated config options, not comments or textual import order.

**Step 2: Run tests and verify RED**

Run the narrow check through the repository test harness, e.g.:

```sh
devenv tasks run test:build-checks
```

If that is too broad for iteration, identify the generated check name from `tests/default.nix` and build only that check. Record the expected failing assertions before implementation.

**Step 3: Implement the archetype boundary**

- Add a reusable `library/archetypes/type-server.nix` that composes the current headless NixOS baseline with the collector modules/options.
- Use the server archetype for `type-server` and `type-server-arm` in `library/machines/catalog.nix`.
- Keep existing backend toggles in place for this first focused change; the immediately following Task 2 moves backend enablement out of the generic/server profiles.
- Preserve per-machine hostnames, disk/hardware configuration, auto-upgrade URLs, and overrides.

**Step 4: Run the focused tests GREEN**

Run the new archetype test and the existing observability tests. Then run `devenv tasks run test:build-checks`.

**Step 5: Review and commit PR 1 changes locally**

Use jj and the conventional message `refactor: extract type-server archetype`. Do not push until the PR's full focused validation passes.

### Task 2: Remove local datastore enablement from generic NixOS server modules

**Files:**
- Modify: `library/archetypes/headless-server-nixos.nix`
- Modify: `library/machines/catalog.nix`
- Modify: `targets/type-server/default.nix`
- Modify: relevant test files under `tests/`

Write a narrow regression test first that asserts the generic headless configuration and type-server profiles do not enable the backend services. Verify RED, remove only the backend enablement/imports necessary for that result, then verify GREEN. Keep `type-nas` node_exporter enabled as an explicit machine-level setting. Do not add Vector to type-nas as part of this PR.

**PR 1 verification:**

```sh
devenv tasks run check:lint
devenv tasks run test:build-checks
```

Also evaluate the affected NixOS configurations with the repository's established eval check.

## PR 2 — Central observability backend and catalog-derived target discovery

### Task 3: Define and test catalog node-exporter inventory

**Files:**
- Create: `library/machines/observability-inventory.nix` (or an equivalently focused helper following existing library conventions)
- Modify: `library/machines/catalog.nix`
- Modify: `library/machines/flake-parts.nix`
- Modify: `library/machines/modules.nix` or the narrowest common machine-module projection point
- Create or extend: `tests/test-observability-inventory.nix`
- Modify: `tests/default.nix`

First add failing tests for:

- exporter-enabled records are included exactly once;
- exporter-disabled records are omitted;
- default endpoint is the machine hostname;
- an explicit hostname/IP override is used verbatim;
- the configured exporter port is preserved, with 9100 as default;
- both NixOS and Darwin records can be represented without self-referencing `self.nixosConfigurations` or `self.darwinConfigurations`.

Run the test and confirm RED. Then add catalog metadata that drives both `myConfig.nodeExporter` enablement and the generated target set. Share the inventory derivation between normal machine configuration projections; avoid maintaining a second handwritten list inside `modules/nixos/prometheus.nix`.

### Task 4: Add server collectors and remote Vector destination

**Files:**
- Modify: `modules/nixos/vector.nix`
- Modify: `modules/nixos/prometheus.nix` and/or a focused node-exporter module if separation is needed
- Modify: `modules/services/node-exporter/darwin.nix`
- Modify: `modules/services/prometheus/darwin.nix`
- Modify: `library/archetypes/type-server.nix`
- Modify: `library/archetypes/headless-server-darwin.nix`
- Modify: `library/archetypes/headless-omlx-darwin.nix`
- Extend: collector and observability tests under `tests/`

Write failing tests for the Vector destination default (`localhost`), remote hostname override, and configured node-exporter listeners/firewall behavior. Verify RED. Then:

- Add a shared collector destination hostname option with a localhost default and wire Vector's Loki URL to it.
- Set collector-only type-server, type-server-arm, and Darwin configurations to point at drlight; drlight retains localhost.
- Keep node_exporter enabled where catalog metadata says it is enabled, including type-nas and configured Darwin targets.
- Configure exporter network access safely: allow scraping over Tailscale by default where applicable; use explicit address/access settings for other networks. Test firewall/listen behavior instead of opening ports globally.
- Leave type-server-arm (Tailscale disabled) and Darwin remote exporter access disabled until explicit per-host addresses/interfaces are available. Keep these exporters in inventory; Prometheus reports them unavailable rather than opening broad access or guessing network details.
- Remove Prometheus/Loki/Alertmanager backend imports and enablement from both Darwin headless archetypes. Retain only their currently configured collectors; do not add Vector to an archetype that does not already use it unless required by the approved design.

### Task 5: Add the `type-observability` backend archetype and wire central Prometheus

**Files:**
- Create: `library/archetypes/type-observability.nix`
- Modify: `library/machines/catalog.nix`
- Modify: `modules/nixos/prometheus.nix`
- Modify: `modules/nixos/loki.nix`
- Modify: `modules/nixos/alertmanager.nix`
- Modify: `targets/drlight/default.nix`
- Extend: `tests/test-nixos-observability.nix` and inventory tests

Write failing tests first proving that:

- `type-observability` enables Prometheus, Loki, and Alertmanager when selected;
- ordinary type-server configurations do not enable those services;
- drlight includes the backend archetype;
- Prometheus scrapes the catalog-generated targets in addition to itself;
- target address defaults and explicit overrides are honored;
- type-nas and Darwin hosts do not run local Prometheus/Loki/Alertmanager after migration.

Verify RED. Add the archetype and configure Prometheus to consume the shared generated inventory. Keep drlight's own exporter in the inventory. Do not use runtime service discovery or Tailscale API credentials. Ensure Prometheus's self-scrape and existing alert rules continue to work.

**PR 2 verification:**

```sh
devenv tasks run check:lint
devenv tasks run test:build-checks
devenv tasks run test:eval
```

Build/evaluate representative NixOS and Darwin configurations; confirm `type-server`, `type-server-arm`, `type-nas`, drlight, `darwin-server`, and `MegamanX` have their expected collector/backend split.

## PR 3 — NixOS Grafana, Caddy ingress, and opnix credentials

### Task 6: Test the NixOS Grafana behavior before implementation

**Files:**
- Create: `modules/nixos/grafana.nix`
- Modify/rewrite: `tests/test-grafana.nix`
- Modify: `tests/stubs.nix`
- Modify: `tests/default.nix`

Before writing the module, add tests that fail while it is absent. Cover:

- Grafana is disabled unless selected by `type-observability`.
- The NixOS service binds to loopback for Caddy proxying and uses the expected port.
- Prometheus and Loki datasources point to local backend URLs using configured ports.
- The existing system-overview dashboard is provisioned and its queries match the central metric/log labels.
- Username/password references use `Grafana - Home/username` and `Grafana - Home/password`, with secret values consumed at runtime rather than embedded in derivation text.
- Drlight config contains the Grafana Caddy route to `http://127.0.0.1:3000`.

Run the focused check and verify RED before implementation.

### Task 7: Implement native NixOS Grafana and remove Darwin Grafana

Use NixOS's native Grafana service and its provisioning options rather than recreating the Darwin launchd script. Preserve the dashboard with corrected Loki selectors as required by the Vector labels. Use opnix-managed secret files for the initial admin username/password, honoring the Homelab default vault without a qualified vault exception.

Remove `modules/services/grafana/darwin.nix`, its import and enablement from the Darwin server archetype, its federation option, and obsolete Darwin-specific test/stub/coverage references. Update Darwin evaluation tests to assert Grafana is not enabled or configured there.

Add the Grafana Caddy app to drlight's target-specific proxy configuration. Do not expose port 3000 directly through the host firewall.

**PR 3 verification:**

```sh
devenv tasks run check:lint
devenv tasks run test:build-checks
devenv tasks run test:eval
```

Run focused Grafana and Darwin archetype checks, then confirm the Grafana systemd unit and provisioning outputs evaluate on x86_64-linux.

## PR 4 — Media-center archetype and drlight cleanup

### Task 8: Test media archetype composition and local-only service presentation

**Files:**
- Create or extend: `tests/test-media-center-archetype.nix`
- Modify: `tests/default.nix`
- Modify as needed: `tests/test-zero.nix` (only assertions that truly describe drlight/zero behavior)

Add failing tests proving:

- `type-media-center` includes `type-server` collector behavior and enables local Jellyfin/media dashboard behavior.
- It does not import or enable the observability backend; drlight obtains that through a separate direct archetype selection.
- Homepage and Caddy advertise only the services active locally on drlight (Jellyfin and Grafana), not the remote seed-box services or stale Sunshine.
- Drlight retains the ZFS media storage configuration and Jellyfin mount dependency.
- Drlight has no backup job, `/var/lib/nixarr` backup path, or Nixarr restic-password secret.

Run the checks and verify RED before changing configuration.

### Task 9: Implement `type-media-center` and migrate drlight

Create `library/archetypes/type-media-center.nix` importing `type-server` and enabling the shared Jellyfin/media-dashboard functionality. Replace drlight's direct headless/media module composition in `library/machines/catalog.nix` with the media archetype plus the direct `type-observability` archetype and target-specific storage. Keep ZFS pool/dataset, disks, hostname/host ID, developer role, Tailscale, Cloudflare/Jellyfin credentials, and service hostnames in machine-specific configuration.

Remove remote seed-box Caddy routes and Homepage links, as well as the Sunshine link. Do not retain commented-out Nix assignments; add only a concise TODO for deferred remote seed-box integration. Keep Jellyfin's active proxy and Grafana's new active proxy. Remove drlight's backup enablement/repository/path/restic secret and backup-module import. Do not enable OnePacerr; remove its import from drlight's composition if it is otherwise inactive.

### Task 10: Full stack validation and PR preparation

Run focused media/archetype checks, then:

```sh
devenv tasks run check:lint
devenv tasks run test:build-checks
devenv tasks run test:eval
devenv tasks run test:all
```

Confirm NixOS target eval for every affected host, Darwin collector-only eval, generated Prometheus inventory, secret references, and absence of remote-seedbox routes/backups. Update test fixtures and stale comments. Create the final stacked PR only after all required checks succeed; no system switch/deployment.

## Commit and stacked-PR checkpoints

Keep implementation commits conventional and local during work. The review stack has these boundaries:

1. PR 1: `refactor: extract type-server archetype` — server baseline and collector behavior.
2. PR 2: `feat: centralize observability backends` — catalog-driven targets, collector routing, and backend composition.
3. PR 3: `feat: move grafana to drlight` — NixOS Grafana, Caddy, opnix credentials, Darwin removal.
4. PR 4: `refactor: add type-media-center archetype` — media composition and drlight cleanup.

Create each branch/PR on top of the preceding stack entry. Keep each PR focused, validated, and reviewable; do not force-push or rewrite commits once pushed. If the repository's current jj PR helper cannot create a stacked base explicitly, use `jj bookmark`/`jj git push` and `gh pr create --base <previous-pr-branch>` following the repository's jj workflow.
