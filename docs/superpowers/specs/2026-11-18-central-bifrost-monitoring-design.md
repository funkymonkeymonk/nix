# Central Bifrost Monitoring Design

## Intent

Upgrade MegamanX Bifrost and collect its Prometheus metrics in drlight's existing Prometheus/Grafana observability stack, keeping the API loopback-bound and metrics access tailnet-restricted.

## Current state and constraints

- drlight runs the central NixOS Prometheus, Loki, Alertmanager and Grafana stack.
- The catalog-derived node exporter inventory already scrapes MegamanX successfully at `MegamanX:9100`.
- MegamanX runs Bifrost HTTP 1.4.9 on loopback port 8081. `/metrics` returns 403 from the management auth middleware. Newer Bifrost releases support the exact client whitelist route `/metrics`.
- Upstream's latest tagged OSS transport release verified during research is `transports/v2.5.1`. Upstream Nix packaging still sets its package version to 1.4.9, so the local package must be adapted and verified rather than blindly updating the input.
- The Tailscale Serve endpoint currently gives remote 404 for Bifrost paths even though local `/v1/models` works. Keep Bifrost loopback-bound; expose only metrics over Tailscale and verify the path end-to-end.
- Bifrost uses a SQLite config database with live provider state. Do not overwrite/reconcile provider/key configuration when adding metrics access.
- Existing unrelated dirty files are user changes and must remain untouched.

## Approaches considered

1. **Expose Bifrost listener on its Tailscale IP directly.** This can expose the UI and full API to the tailnet. Rejected as too broad.
2. **Upgrade then whitelist `/metrics`, serve the entire Bifrost API to the tailnet, and rely only on Prometheus configuration.** Operationally simple but broadens access to inference and UI/API. Rejected.
3. **Upgrade to tagged OSS v2.5.1, configure exact `/metrics` whitelist without disturbing existing SQLite-backed provider state, and publish only that path over Tailscale.** Selected. Preserve existing loopback listener and use drlight's central Prometheus. If Tailscale Serve cannot safely preserve/map the path, use a small dedicated reverse proxy bound to the MegamanX Tailscale address that forwards only GET `/metrics` to localhost Bifrost.

## Goals

- Upgrade the Bifrost HTTP package to tagged OSS 2.5.1 while keeping Nix package/UI/vendor patches compatible.
- Persistently permit `/metrics` in Bifrost's management auth settings without changing current providers or API credentials.
- Make only the metrics endpoint reachable to drlight over the tailnet.
- Configure drlight Prometheus to scrape `megamanx:8081/metrics` or a dedicated verified metrics port/path, with a stable `host="MegamanX"` label.
- Add tests for Nix package version/config and generated Prometheus target configuration.
- Verify model listing and inference path continue to work after upgrade, plus `/metrics` returns Prometheus exposition locally and remotely.

## Non-goals

- Enable a local Prometheus on MegamanX.
- Add oMLX application metrics unless its server documents and exposes them.
- Alter provider/model/API-key data in the existing SQLite database.
- Change Grafana dashboards in this initial implementation.

## Deployment boundary

Code/config changes are not permission to deploy. The package build, local config evaluation, and tests can run in the repository. Applying the machine change must use the required Machines plan/review/apply workflow after commit, with the exact reviewed plan ID. Verify the running version, model listing, `/metrics`, tailnet-only reachability, Prometheus target health, and existing Vector-to-Loki delivery after deployment.

The upgrade can be implemented separately from metrics exposure. Metrics remain blocked until the exact Bifrost v2.5.1 source-of-truth/reconciliation behavior for adding `client.whitelisted_routes` to an existing SQLite config is verified without modifying the active provider/key state. Do not enable a Prometheus scrape or install a route that cannot be tested end-to-end.
