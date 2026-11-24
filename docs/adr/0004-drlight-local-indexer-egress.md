# ADR 0004: Run Indexer Management Locally with Ultra Egress

**Status:** Accepted  
**Date:** 2026-11-23

## Context

Prowlarr and FlareSolverr were initially kept on Ultra so indexer requests used seedbox egress, while the Arr applications moved to Drlight. Ultra's Tailscale beta could not initiate connections to Drlight's Arr APIs. The Ultra proxy is reachable from Drlight over its public HTTP endpoint; an unauthenticated challenge confirmed HTTP Basic authentication. Ultra's Tailscale address does not expose the proxy port, and its SSH server rejects TCP forwarding.

The user wants the Arr applications and Prowlarr co-located on Drlight while continuing to keep indexer requests off the home public IP. The user accepts Ultra's public HTTP proxy transport risk and keeps its dedicated password in the default Opnix vault.

## Decision

1. Run Prowlarr and FlareSolverr as Drlight NixOS services next to Radarr, Sonarr, and Jellyfin.
2. Configure Prowlarr's local Arr application URLs and FlareSolverr endpoint over loopback. Keep the Prowlarr UI on private home-LAN/Tailscale interfaces, and do not open or publish a FlareSolverr firewall port.
3. Route indexer requests through Ultra's public authenticated HTTP proxy. Store the proxy credentials only in Prowlarr's runtime database, populated from the `Ultra.cc HTTP Proxy` Opnix item. Bypass the proxy for local-address requests.
4. Keep Ultra's Prowlarr/FlareSolverr installations and state available for rollback until local backup restore, proxy egress, indexer sync, and FlareSolverr tests pass. Only one Prowlarr instance may actively sync the Arr apps at a time.
5. Keep Transmission on Ultra. Drlight's Arr apps continue to manage it through their existing RPC configuration and use the established copy-only completed-download staging path.
6. Enable OnePacerr on Drlight for the existing Jellyfin library with downloads disabled initially. It may organize existing files and update metadata only after a restorable backup/snapshot and the exact library path are verified. Enabling OnePacerr torrent downloads is deferred to a separate design and path-mapping review.

## Consequences

- Indexers observe Ultra egress rather than Drlight's home public IP. Ultra observes the client source and proxy destinations.
- The Drlight-to-Ultra proxy hop is plain HTTP with Basic authentication. An on-path observer could recover the dedicated proxy password and see the CONNECT destination; HTTPS payload contents remain encrypted after CONNECT. The user accepts this tradeoff. The proxy password is separate from UCP/SSH credentials.
- Prowlarr's service lifecycle and private network boundary are managed by Nix; its runtime indexer list, proxy settings, and app database remain operator-managed and are migrated with a version-compatible native backup.
- OnePacerr can mutate the existing library at startup. Downloads remain disabled in this phase, and its mount is limited to the target library subtree.
- No Ultra service, torrent, download, media, or cleanup data is deleted by this decision.
