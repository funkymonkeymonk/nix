# Drlight Media Automation: Prowlarr, FlareSolverr, OnePacerr, and Ultra Transmission

**Status:** Draft for user approval  
**Date:** 2026-11-23

## Intent

Complete Drlight's media automation stack by moving Prowlarr and FlareSolverr from Ultra.cc to Drlight and enabling OnePacerr for its existing Jellyfin series. Keep Transmission on Ultra.cc. Keep indexer egress on Ultra by configuring Prowlarr to use Ultra's authenticated HTTP proxy.

## Goals

- Manage Prowlarr and FlareSolverr as Drlight NixOS services alongside the existing Radarr, Sonarr, and Jellyfin services.
- Preserve existing Prowlarr settings/indexers with its supported backup and restore workflow.
- Connect Prowlarr to Drlight-local Sonarr/Radarr over loopback and FlareSolverr over loopback.
- Route indexer requests through Ultra's HTTP proxy using the `Ultra.cc HTTP Proxy` item in Drlight's default `Opnix` vault. Keep secret values and live endpoint details out of Git and logs.
- Enable OnePacerr on Drlight for its existing Jellyfin series. Disable downloads initially, but allow it to organize existing files and update Jellyfin metadata.
- Preserve the existing Arr-to-Ultra Transmission RPC setup and completed-download staging. Verify those integrations rather than moving Transmission or changing the cleanup policy.
- Keep service UIs private and FlareSolverr internal; do not publish them through public Caddy or the public firewall.
- Update the Drlight migration guide and mark superseded OnePacerr/Ultra placement notes so they describe the new ownership and rollback behavior.

## Non-goals

- Do not move Transmission to Drlight or enable OnePacerr's torrent-download integration in this phase. Connecting OnePacerr directly to Ultra Transmission and mapping its completed files through Drlight staging is a later, separately reviewed phase.
- Do not change Ultra's Tailscale/SSH settings, use an exit node, expose Arr APIs publicly, or configure OnePacerr to delete torrents/files.
- Do not uninstall or delete Ultra Prowlarr, FlareSolverr, Transmission, their state, or any media/download data as part of implementation or validation.
- Do not deploy or perform live cutover until a separate reviewed Machines plan is approved.

## Approaches considered

1. **Keep Prowlarr on Ultra and reach Drlight over Tailscale.** Not viable with the observed configuration: Ultra's outbound request to Drlight timed out, the Ultra Tailscale IP refused port 8080, and Ultra's SSH server rejected TCP forwarding as administratively prohibited.
2. **Run Prowlarr on Drlight with direct home egress.** Simpler, but indexers would see Drlight's home public IP; not selected.
3. **Run Prowlarr locally and use Ultra's public HTTP proxy.** Selected. An unauthenticated request from Drlight received Squid's `407` response with `Proxy-Authenticate: Basic`, confirming availability and the authentication scheme. The user accepts the plaintext home-to-proxy hop so indexers see Ultra's egress IP instead of the home IP.
4. **Move Transmission to Drlight.** Not selected. Drlight already manages Ultra Transmission over RPC, and retaining the seedbox preserves the existing download/staging architecture.
5. **Enable OnePacerr downloads immediately.** Deferred. The user selected existing-library processing first; active torrent submission needs additional path/ownership validation against the Ultra download root and Drlight staging.

## Design

### Prowlarr and FlareSolverr

- Enable the pinned nixpkgs `services.prowlarr` and `services.flaresolverr` modules on Drlight. Current pinned package evaluation reports Prowlarr `2.6.5.5623` and FlareSolverr `3.5.2`; verify deployed Ultra versions and restore compatibility before importing state.
- Keep Prowlarr's UI available only on Drlight's existing home-LAN and Tailscale interfaces, with no global firewall opening or Caddy route. Do not open FlareSolverr's port to LAN, tailnet, or the public internet; Prowlarr reaches it at `127.0.0.1:8191`.
- Configure Prowlarr's server URL as `http://127.0.0.1:9696` and its Sonarr/Radarr application URLs as their Drlight loopback endpoints. Bypass the proxy for local addresses so Arr API calls and FlareSolverr's local API remain local.
- Configure Prowlarr's General HTTP Proxy with the Ultra service host from the UCP Connect page, port `8080`, service username, and dedicated HTTP-proxy password from the Opnix item. Keep those values in Prowlarr runtime state only, not Nix expressions, command lines, or logs.
- The public Ultra proxy uses HTTP Basic authentication. An on-path observer could recover the dedicated proxy password and see the CONNECT destination. HTTPS indexer contents remain TLS-encrypted after CONNECT; Ultra sees the source and proxy destinations, while indexers see Ultra's egress IP. This transport risk is explicitly accepted for this setup. The proxy password is separate from UCP/SSH credentials.
- The pinned Prowlarr `2.6.5.5623` FlareSolverr integration forwards its configured General Proxy URL and credentials to FlareSolverr for challenge requests. No separate proxy credential injection into the FlareSolverr service is needed; verify ordinary and FlareSolverr-backed requests during cutover.

### OnePacerr

- Import and enable the existing `modules/nixos/onepacerr.nix` module on Drlight, replacing its current minimal stub. The stub only sets a series name, torrent-client type, and `localhost` Jellyfin URL; it lacks Jellyfin credentials, library mounts, and working container-to-host network configuration.
- Pin OnePacerr to the upstream `v1.8.16` release instead of `latest`. Drlight's OCI backend currently evaluates to Podman; use its generated `podman-onepacerr` systemd service and bridge network. Configure `LIBRARY_MEDIA_SERVER=jellyfin`, the existing One Pace series, and a Jellyfin URL reachable from the container (for example, the verified `host.containers.internal` gateway). Do not use host networking or publish OnePacerr's status/UI port.
- Reuse Drlight's existing Jellyfin admin credentials from the default `Opnix` vault, delivered to the container through a mode-restricted runtime environment file generated from Opnix secret files. Do not create a new Jellyfin identity in this change, place credentials in the Nix store, or put secret values in OCI environment literals.
- Verify the existing Jellyfin series and filesystem path before enabling the container. Mount only the required library subtree read/write and configure explicit library path mappings if Jellyfin's path differs from the container mount. Fail closed if the existing series is absent rather than creating a duplicate library entry.
- Set `PIPELINE_SKIP_DOWNLOADS=true`; omit OnePacerr's torrent-client credentials and URL in this phase. Enable existing-file organization and metadata updates, as selected by the user. Before its first mutating run, verify a restorable backup or snapshot of the affected library.
- OnePacerr will auto-start in this library-only mode after the backup/path preflight passes. Keep verification hashing at the upstream default unless implementation testing finds a reason to change it.
- Since OnePacerr will modify files under its library path, verify that the target folder will not conflict with a Sonarr-managed series. Keep Drlight's existing Arr roots and library data intact.
- Container-to-host Jellyfin access must use a reachable bridge host address, not `localhost` inside the container. Do not use broad host networking; publish no container ports and grant only the required library mount.

### Transmission and staging

- Keep Transmission on Ultra. Drlight already enables `myConfig.mediaManagement.radarr.transmission.enable`, `.sonarr.transmission.enable`, and `.lidarr.transmission.enable`; reconciliation uses runtime RPC credentials/URL and the existing mapping to local staging.
- Preserve this configuration and add/extend tests proving Arr download-client integrations remain enabled and no Transmission service is moved or publicly exposed.
- Validate the existing Arr RPC connections and staging configuration during preflight. OnePacerr itself will not contact Transmission while downloads are disabled; do not alter seeding, staging, or cleanup behavior.

## Migration and rollback

- Inventory source and pinned destination versions before restoring Prowlarr. Create and verify a Prowlarr-native backup outside the repository; stop if restore would require an unsupported downgrade or conversion.
- Keep Ultra Prowlarr/FlareSolverr installed and retain their state. Avoid having both Prowlarr instances sync the same Arr apps simultaneously at cutover; preserve Ultra as the rollback copy until local proxy/indexer/FlareSolverr/Arr tests pass.
- Before OnePacerr's first organization/metadata run, verify the existing library path and a restorable backup/snapshot. If validation fails, disable OnePacerr and retain the original data and Ultra services.
- No Transmission removal, download cleanup, staging policy change, or OnePacerr torrent submission is part of this phase.

## Validation gates

- Add Nix evaluation coverage for Prowlarr/FlareSolverr service enablement, private listener/firewall behavior, OnePacerr's pinned OCI image/runtime secret wiring/mounts, and preservation of remote Arr-to-Transmission integration.
- Run repository lint, build-checks, and NixOS evaluation after implementation.
- Before cutover, verify source backup/version compatibility; configure the Ultra proxy from the Opnix item in local Prowlarr runtime settings; test that Prowlarr's observed egress is Ultra; and verify FlareSolverr challenge requests use the same proxy.
- Before OnePacerr's first mutating run, verify Jellyfin authentication, path mappings, permissions, existing show identity, and backup/snapshot. Run with downloads disabled.
- Use the repository's Machines plan/apply/check workflow for Drlight deployment. Deployment, stopping old Ultra apps, and later enabling OnePacerr downloads require separate approval.

## Assumptions and implementation calls

- “Local” means Drlight, where Sonarr, Radarr, and Jellyfin already run.
- “Manage Transmission directly” means preserving and validating Drlight's existing Arr-to-Ultra Transmission RPC integration; OnePacerr's torrent submission remains disabled in phase one.
- Reuse Drlight's existing Jellyfin admin credentials because OnePacerr requires username/password and the repository already provisions that identity. Restrict OnePacerr's filesystem mount to the verified One Pace library subtree.
- The user accepts the public Ultra HTTP proxy's Basic-auth transport risk and has the proxy password plus connection details in the `Ultra.cc HTTP Proxy` item in the `Opnix` default vault.
