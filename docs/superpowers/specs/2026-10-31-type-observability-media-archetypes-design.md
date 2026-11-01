# Server, Media-Center, and Observability Archetypes

**Status:** Draft for user review (2026-10-31)  
**Decision:** Separate reusable server and media-center profiles from a dedicated observability-backend archetype, with drlight hosting the centralized observability stack.  
**Scope:** NixOS/Darwin archetype composition, collector routing, Prometheus target generation, Grafana migration, and drlight media configuration cleanup. Implementation will be delivered as a sequence of stacked, independently reviewable PRs after this spec is approved.

## Goals

- Make `type-server` a reusable archetype rather than only a machine entry in the machine catalog.
- Make `type-media-center` inherit the server archetype while keeping media-center behavior out of the generic server profile.
- Put observability datastores, alerting, and visualization in a separate `type-observability` archetype, included directly by drlight.
- Run a centralized Prometheus/Loki/Alertmanager/Grafana backend on drlight, with collectors on configured machines.
- Generate Prometheus node-exporter targets from this repository's machine inventory, including Darwin machines, without runtime network scanning or Tailscale API credentials.
- Move Grafana from Darwin to NixOS, expose it through Caddy on drlight, and manage its username/password through opnix.
- Keep media hardware, addresses, backup destinations, and credentials host-specific.
- Remove active configuration for remote seed-box services from drlight until their integration is implemented.
- Deliver changes in a reviewable stack of PRs, with automated tests written before implementation.

## Non-goals

- Enabling or migrating the remote seed-box applications onto drlight.
- Building a runtime service-discovery daemon or querying Tailscale's control plane/API.
- Changing which machines exist in the catalog or renaming the existing `type-server-arm` machine output.
- Deploying configurations to any live machine or performing a system switch.
- Adding a Linux Grafana implementation to any host other than the drlight observability stack.
- Backing up the remote seed-box's state from drlight.

## Current findings

- `type-server`, `type-server-arm`, `type-nas`, and `drlight` currently use `library/archetypes/headless-server-nixos.nix`. That module imports the Prometheus wrapper and enables both Prometheus and node_exporter. `type-server/default.nix` additionally enables Vector, Loki, and Alertmanager.
- The Darwin `headless-server-darwin` archetype enables Prometheus, node_exporter, Loki, Vector, Alertmanager, and Grafana. The `headless-omlx-darwin` archetype enables a local Prometheus and node_exporter. Those hosts will become collector-only.
- `modules/nixos/prometheus.nix` currently configures both the Prometheus server and node_exporter. Prometheus scrapes only itself and a local node_exporter; the wrapper will need catalog-derived remote targets.
- `modules/nixos/vector.nix` ships logs to Loki, defaulting to `http://localhost:3100`. A collector-level destination-host setting will allow remote collectors to ship to drlight while preserving localhost as the option default.
- The catalog is the shared source for NixOS and Darwin machine composition. Target inventory must be derived from catalog declarations, not by evaluating `self.nixosConfigurations`/`self.darwinConfigurations` from within the Prometheus configuration (which risks recursive evaluation).
- Drlight currently enables Jellyfin and defines media storage, Caddy routes, Homepage links, a backup job for `/var/lib/nixarr`, and a disabled OnePacerr module. The remote seed-box applications referenced in Caddy/Homepage are not configured as local NixOS services. The backup path is the only configured path and will be removed, so the backup job will be disabled.
- `modules/services/grafana/darwin.nix` provisions Prometheus and Loki datasources and a system-overview dashboard, and includes an obsolete optional type-server federation datasource. The new centralized Prometheus will scrape configured node exporters directly, so this federation option is unnecessary.
- Drlight uses the `Homelab` 1Password default vault. The user supplied `op://Homelab/Grafana - Home/username` and `op://Homelab/Grafana - Home/password`. Nix configuration must use unqualified `Grafana - Home/username` and `Grafana - Home/password` references so the shared opnix helper applies the configured default vault.

## Architecture

### `type-server` archetype

Create a reusable NixOS archetype that composes the existing headless server baseline with the observability collector group. The collector group consists of:

- `node_exporter`, which exposes host metrics for Prometheus to scrape.
- Vector, which ships logs to the selected Loki destination.

`type-server` and the existing `type-server-arm` machine use this archetype and enable these collectors by default. `type-media-center` inherits this archetype, so drlight also receives the collectors. The machine catalog declares the effective node_exporter setting for each host; the archetype's collector profile and catalog metadata must be wired so this declaration both enables the exporter and generates the scrape target, with no separately maintained duplicate target list. The collector destination option defaults to `localhost`; machines without a local backend set it to drlight's reachable hostname/address.

The generic headless NixOS baseline must not enable a Prometheus datastore by default. `type-nas` will keep its existing node_exporter collection capability but lose its local Prometheus backend so the central Prometheus can scrape it. It will not gain Vector unless explicitly configured; its current configuration does not enable Vector.

Machine identity, disk configuration, hardware modules, auto-upgrade URLs, and user-specific settings remain in machine configuration/catalog metadata rather than being inherited from another machine target.

### `type-media-center` archetype

Create a reusable media-center archetype that imports `type-server` and adds the common Jellyfin/media-dashboard functionality. `drlight` selects this archetype rather than composing the headless server and media modules separately.

Media storage stays in `targets/drlight` because `modules/nixos/media-storage.nix` assumes drlight's named ZFS pool and datasets. Jellyfin remains enabled through the shared media configuration and continues to require `/srv/media` to be mounted before service start.

Do not enable OnePacerr or any remote seed-box service locally. Remove the inactive OnePacerr module from drlight's composed module list if it has no other active consumer; retain the reusable module source unless a later cleanup demonstrates it is dead code.

The Homepage dashboard should advertise only services that are active locally on drlight. Remove the seed-box service links and the stale Sunshine link. Remove the corresponding localhost Caddy routes for remote seed-box apps; leave a concise TODO noting that remote seed-box integration is deferred, rather than retaining commented-out Nix assignments. Keep the local Jellyfin route.

### `type-observability` archetype

Create a NixOS archetype that enables the observability backend services:

- Prometheus for metrics storage, rule evaluation, and scraping.
- Loki for log storage.
- Alertmanager for alert routing.
- Grafana for visualization.

Drlight includes this archetype directly alongside `type-media-center`; `type-media-center` does not include `type-observability`. Ordinary type-server machines get collectors without datastore/visualizer services.

Move the Prometheus/Loki/Alertmanager backends off the Darwin server archetypes and make those hosts collector-only. Remove the Darwin Grafana module and its imports, tests, and references. Keep Darwin node_exporter/Vector collector functionality where it is currently enabled, with its log destination directed to drlight.

### Catalog-derived Prometheus target inventory

Extend the machine catalog with declarative node-exporter metadata that is the source of truth for exporter enablement and Prometheus discovery. The metadata indicates whether a machine runs node_exporter, uses the existing configured exporter port unless overridden, and may specify a scrape hostname/IP override. Machine module generation consumes this metadata to enable the exporter; the same records generate Prometheus targets. Derive targets from only enabled entries across NixOS and Darwin machine records.

- Default scrape address: the machine's catalog hostname.
- Optional override: an explicit hostname or IP address per machine.
- Port: use that machine's configured node_exporter port, defaulting to the existing `9100` value.
- Keep drlight's own exporter in the generated inventory using its normal machine address; do not special-case runtime discovery.
- The target set is configuration-derived, not a live inventory of online machines. Offline/unreachable configured nodes remain targets and appear unavailable in Prometheus.
- For hosts with remote scrape access configured, ensure exporters listen on an address reachable from drlight and permit traffic only on the intended network path. Tailscale is the normal path; non-Tailscale/LAN endpoints require explicit per-machine address/access configuration. Do not expose exporter ports broadly by default.
- Until explicit network access is configured, keep the `type-server-arm` (Tailscale disabled) and Darwin exporters inaccessible remotely while retaining their catalog targets; Prometheus will show those targets as unavailable. Do not guess addresses/interfaces or open exporter ports broadly to make them reachable.

Vector's Loki destination host is a separate collector-group setting. Its default remains `localhost`; type-server, type-server-arm, type-nas if Vector is later enabled, and collector-only Darwin machines set the destination to drlight as appropriate. Drlight keeps the default because it hosts Loki locally.

### Grafana on NixOS behind Caddy

Add a NixOS Grafana module using the native NixOS Grafana service. Enable it only through `type-observability`. Provision Prometheus and Loki datasources against local backend addresses and carry forward the existing system-overview dashboard, adapting its queries to the centralized target/label model.

Bind Grafana to loopback because Caddy is the intended ingress. Add a drlight-specific Caddy route at `grafana.home.buildingbananas.com` with upstream `http://127.0.0.1:3000`, preserving Caddy's existing private-network restrictions and Cloudflare secret handling.

Provision the configured Grafana username and password from opnix-managed runtime secret files. Use the unqualified references `Grafana - Home/username` and `Grafana - Home/password`; do not put secret values in Nix expressions or the Nix store. Do not use Grafana's default admin credential as the production configuration.

### Drlight-specific configuration

Drlight composes `type-media-center`, `type-observability`, and its machine target. Keep these settings in the machine target/catalog:

- Hostname, host ID, platform, disk/filesystem labels, and ZFS media pool.
- `mkUser`, developer role, and Tailscale configuration.
- Caddy hostnames and upstreams for local Jellyfin and Grafana.
- Cloudflare and Jellyfin credentials.
- Machine-specific exporter address override only if the catalog hostname is not reachable from the central Prometheus.

Remove the backup enablement, backup repository configuration, restic-password secret, and backup-module import from drlight's composition because `/var/lib/nixarr` was its only path. Do not alter the ZFS media dataset or infer that the media library itself should be backed up.

## Components expected to change

- `library/archetypes/`: introduce the `type-server`, `type-media-center`, and `type-observability` compositions; remove observability backends from generic headless profiles.
- `library/machines/catalog.nix`: compose machine records from archetypes and provide exporter inventory metadata/optional address overrides.
- `targets/type-server`, `targets/type-server-arm`, `targets/type-nas`, `targets/drlight`, and relevant Darwin archetypes/targets: move enablement and per-host values to their proper ownership layers.
- `modules/nixos/prometheus.nix` and collector modules: use the generated target inventory and configurable Vector destination; ensure safe network access to exporters.
- `modules/nixos/grafana.nix` (new): native NixOS service, datasource/dashboard provisioning, and runtime secret integration.
- `modules/services/grafana/darwin.nix` (remove): delete Darwin-only service implementation and federation behavior.
- `modules/nixos/homepage.nix` and drlight Caddy settings: remove inactive remote seed-box/Sunshine links/routes and add Grafana ingress.
- Observability, machine inventory, Grafana, and drlight tests: update/add regression coverage; replace stale assertions referring to Darwin Grafana or type-server-local Prometheus.

Exact file allocation may be adjusted to follow the repository's module patterns, but the behavior and boundaries above are fixed by this design.

## Stacked PR sequence

Each PR is based on the preceding PR in the stack and has a focused test set. No PR deploys to a live machine.

1. **Extract the reusable type-server archetype and collector group.** Separate generic headless NixOS settings from collector/backend toggles, introduce `type-server`, and use it on the existing type-server and ARM server records. Preserve type-nas's node exporter explicitly while removing implicit datastore behavior from the generic headless baseline. Add composition/default tests.
2. **Centralize observability backends and target inventory.** Add `type-observability` with Prometheus/Loki/Alertmanager, generate Prometheus targets from catalog exporter metadata, add address overrides and Vector destination-host configuration, move type-nas and Darwin hosts to collector-only behavior, and compose the backend on drlight. Add target inventory, scrape config, and network-access tests.
3. **Move Grafana to NixOS and add Caddy/secret wiring.** Remove Darwin Grafana and obsolete federation tests/references; add native NixOS Grafana, provision datasources/dashboard, inject username/password via opnix, and expose it through Caddy on drlight. Add NixOS service, provisioning, secret-reference, and route tests.
4. **Add type-media-center and finish drlight cleanup.** Make it inherit type-server, compose it on drlight, retain Jellyfin and machine-specific ZFS configuration, remove inactive local seed-box routes/dashboard entries and OnePacerr enablement/import where appropriate, and remove the empty backup job/secret. Add archetype composition and cleanup regression tests.

If implementation reveals that a PR cannot be evaluated independently without behavior temporarily violating an already-approved requirement, adjust the order or split while keeping each review boundary focused. Each stack entry should have a clear title/body and only be opened after its parent is reviewable.

## Test-first acceptance criteria

Tests must be written first for each PR and verified to fail before implementation. The implementation is complete when:

- `type-server`, `type-media-center`, and `type-observability` compose with the stated inheritance and boundaries.
- `type-server` and `type-server-arm` have collectors enabled without local Prometheus/Loki/Alertmanager/Grafana.
- `type-nas` retains node_exporter and no longer runs local Prometheus.
- Darwin collector hosts retain configured exporters/shippers, no longer run local observability datastores/Alertmanager/Grafana, and route logs to drlight.
- Prometheus includes exactly the catalog entries configured for node_exporter, uses hostname defaults and explicit address overrides correctly, and does not require a runtime Tailscale API credential.
- Exporter network exposure is limited to configured interfaces/routes; Tailscale is the default path and an explicit address/access override supports other reachable networks.
- Vector uses localhost by default and honors the collector group destination override.
- Grafana runs only on the NixOS observability host, provisions central Prometheus/Loki datasources and the dashboard, uses opnix-provided credentials without embedding secret values, and is reachable through the drlight Caddy route.
- Drlight keeps Jellyfin and its ZFS media storage; local proxy/dashboard configuration no longer claims the remote seed-box apps or Sunshine are local; no backup job or Nixarr-state secret/path remains.
- `devenv tasks run check:lint`, `devenv tasks run test:build-checks`, and relevant NixOS/Darwin evaluation tests pass. Full `devenv tasks run test:all` is required before the final PR in the stack.

## Risks and mitigations

- **Inventory/config drift:** use catalog metadata as the single source for target generation and exporter enablement; add eval assertions covering representative NixOS and Darwin hosts.
- **Hostname resolution varies by network:** default to catalog hostname and support explicit IP/hostname override. Keep unreachable configured targets visible rather than silently dropping them.
- **Exporter exposure:** restrict scrape access to the configured network interface/path; do not open node_exporter broadly to all interfaces by default.
- **Nix module composition duplicates or conflicts:** keep archetypes as reusable NixOS modules, not imports of machine target modules; evaluate each affected host in its PR.
- **Grafana secret leakage:** use opnix runtime files and the machine's Homelab default vault; do not interpolate credentials into store-backed settings.
- **Remote-service configuration drift:** remove inactive localhost routes/dashboard links and document the deferred remote seed-box integration without leaving commented-out Nix code.
- **Stack dependency reviewability:** each PR has scoped tests and is stacked on the previous PR; do not push a child PR before its parent is available for review.

## Approval boundary

This document is submitted for user review. Implementation planning and code changes begin only after the user approves this spec. After approval, create a detailed implementation plan with exact test-first tasks, then execute each task as a separately reviewable stacked PR. No live system switch is part of the work.
