# Drlight-local Prowlarr and FlareSolverr

**Status:** Draft for user approval  
**Date:** 2026-11-23

## Intent

Move Prowlarr and FlareSolverr from Ultra.cc to Drlight, alongside the existing Radarr and Sonarr services. This removes the failed Ultra-to-Drlight Tailscale path from Arr integration. Keep indexer egress on Ultra by configuring Prowlarr to use Ultra's authenticated HTTP proxy.

## Goals

- Manage Prowlarr and FlareSolverr as Drlight NixOS services using the pinned nixpkgs service modules.
- Preserve the existing Prowlarr indexers and settings with an application-native backup/restore; keep the Ultra source state available for rollback.
- Connect Prowlarr to Drlight-local Sonarr and Radarr over loopback, and connect FlareSolverr over loopback.
- Route Prowlarr indexer traffic through Ultra's HTTP proxy on port 8080. Configure its credentials from the `Ultra.cc HTTP Proxy` item in Drlight's default `Opnix` vault; never put secret values or live endpoints in Git or logs.
- Keep Prowlarr's UI available only on private interfaces. Do not publish either service through public Caddy or the public firewall.
- Update the current Drlight migration runbook so it no longer directs operators to keep Prowlarr and FlareSolverr on Ultra.

## Non-goals

- Do not change Ultra's Tailscale or SSH forwarding configuration, use an exit node, or expose Arr APIs publicly.
- Do not remove or uninstall the Ultra Prowlarr/FlareSolverr instances or delete their data as part of this change.
- Do not deploy or perform the live cutover until a separate reviewed Machines plan is approved.

## Approaches considered

1. **Keep Prowlarr on Ultra and reach Drlight over Tailscale.** Not viable with the observed configuration: Ultra's outbound request to Drlight timed out, the Ultra Tailscale IP refused port 8080, and Ultra's SSH server rejected TCP forwarding as administratively prohibited.
2. **Run Prowlarr locally with direct egress.** Simple, but indexers would see Drlight's home public IP; not selected.
3. **Run Prowlarr and FlareSolverr locally, proxy through Ultra's public HTTP proxy.** Selected. An unauthenticated request from Drlight received Squid's `407` response with `Proxy-Authenticate: Basic`, confirming the public proxy endpoint is reachable and uses Basic authentication. The user accepts using this endpoint despite the plaintext home-to-proxy hop in order to keep indexers from seeing the home IP.

## Design

- Enable the pinned nixpkgs `services.prowlarr` and `services.flaresolverr` modules on Drlight. The current pinned packages evaluate to Prowlarr `2.6.5.5623` and FlareSolverr `3.5.2`; source versions must be checked before restoring state.
- Keep Prowlarr's web UI on private access only (Drlight's existing home-LAN/Tailscale boundary). Do not open FlareSolverr's port to LAN, tailnet, or the public internet; Prowlarr reaches it at `127.0.0.1:8191`.
- Configure Prowlarr's own server URL as `http://127.0.0.1:9696` and its Sonarr/Radarr application URLs as their Drlight loopback endpoints. Enable proxy bypass for local addresses so these app API calls remain local.
- Configure Prowlarr's General HTTP Proxy with the Ultra service hostname/IP, port `8080`, service username, and dedicated HTTP-proxy password from the `Ultra.cc HTTP Proxy` Opnix item. Enable local-address bypass so loopback Arr/FlareSolverr calls stay local. Keep credentials in Prowlarr runtime state only, not Nix expressions, command lines, or logs.
- The pinned Prowlarr `2.6.5.5623` FlareSolverr integration forwards its configured general-proxy URL and credentials to FlareSolverr for challenge requests. No separate proxy credential injection into the FlareSolverr systemd service is needed; verify both ordinary and FlareSolverr-backed requests during cutover.
- Keep Prowlarr's runtime app and proxy settings operator-managed in its restored application state; Nix owns service availability, private network exposure, and backup/recovery documentation, not indexer credentials or endpoint literals.
- The proxy hop from Drlight to Ultra is plain HTTP with Basic authentication. An on-path observer could recover the dedicated proxy password and see the CONNECT destination. HTTPS indexer contents remain TLS-encrypted after CONNECT; Ultra sees the source and proxy destinations, and indexers see Ultra's egress IP. This risk is explicitly accepted for this setup. The proxy password is separate from UCP/SSH credentials.
- Back up Prowlarr using its supported backup workflow to a protected location outside the repository. Restore only after comparing source and destination versions and confirming the supported restore path. Keep the Ultra source copy intact. At cutover, avoid having both Prowlarr instances sync the same Arr apps simultaneously; retain Ultra for rollback until local proxy, indexer, FlareSolverr, and Arr tests pass.

## Validation and cutover gates

- Add Nix evaluation tests for the two enabled Drlight services, their private ports, and the absence of public Caddy/firewall exposure for FlareSolverr.
- Run repository lint, build-checks, and NixOS evaluation after implementation.
- Before cutover, validate the source backup/version compatibility and configure the Ultra proxy in the local Prowlarr runtime UI using the Opnix-stored values. Test the proxy through Prowlarr and verify its observed egress is Ultra; test FlareSolverr only against the existing configured indexers that require it.
- Keep the Ultra services and source data available until all local checks pass. Deployment and stopping the old Prowlarr remain separate reviewed operational steps.

## Assumptions

- “Local” means Drlight, where Sonarr and Radarr already run.
- The user accepts the public Ultra HTTP proxy's Basic-auth transport risk; the credential is dedicated to proxy use and is not an account or SSH password.
- The Ultra proxy fields are stored in the `Ultra.cc HTTP Proxy` secure item in the `Opnix` default vault. No endpoint or credential value belongs in this design or source control.
