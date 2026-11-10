# Ultra.cc and Drlight Media Management and Retention Design

**Status:** Expanded design approved in chat; awaiting user review of this specification  
**Date:** 2026-11-09

## Goal

Make Drlight the authoritative local media library and host its library-management apps, while keeping Ultra.cc responsible for torrent downloading, seeding, and indexer access. Reclaim Ultra.cc storage only after rsync has copied completed torrent data to Drlight, the Arr apps have imported it into the local library, and the seeding and private-tracker account rules allow removal.

The retention defaults remain:

- Keep a completed torrent until it has accumulated **240 hours of actual seeding OR reached a per-torrent upload/download ratio of 3.0**, whichever occurs first.
- For every associated private tracker, require the account-wide ratio to be **at least 0.6**. Treat unknown tracker classification or unavailable ratio data as ineligible.
- Verify local copies with rsync's normal size-and-modification-time comparison. Do not add checksum verification.

## Service placement

### Drlight

Drlight owns the ZFS-backed local library at `/srv/media` and runs:

- Jellyfin;
- Radarr, Sonarr, Lidarr, Mylar3, and Bazarr.

The existing Arr application databases/settings should be migrated so monitored media, profiles, histories, and other user configuration are preserved. Update their library roots to Drlight's local media roots. Bazarr connects to Drlight's local Sonarr/Radarr APIs.

### Ultra.cc

Ultra.cc continues to run:

- Transmission, which retains and seeds the original torrent data;
- Prowlarr, which remains the indexer manager and request proxy;
- FlareSolverr, if the current Prowlarr configuration uses it.

Keep Prowlarr and FlareSolverr together on Ultra.cc so indexer traffic and any FlareSolverr challenge handling continue to use the seedbox's egress IP. Keep Prowlarr's normal proxy behavior; preflight the `Redirect` setting for each configured indexer because a redirect can cause an Arr app on Drlight to contact an indexer directly. Prowlarr's current indexers are public. Private trackers may have different IP/account policies; check each tracker's rules before adding one.

## Private application connectivity

Use the Ultra.cc Tailscale application to provide private connectivity from Prowlarr on Ultra.cc to the Arr APIs on Drlight. Ultra.cc documents its Tailscale application as beta, so the preflight must verify the service can connect through the app's network namespace to Drlight before relying on it. If it cannot, stop and revise the design; do not expose Arr APIs publicly as a fallback. Tailscale connectivity is required for Prowlarr's App sync; Drlight Arr APIs must be reachable from the Ultra tailnet identity only.

Drlight's Arr APIs must be reachable only over the intended tailnet path and protected with their normal API authentication. Keep Transmission and Prowlarr URLs/API keys in runtime secret configuration through OpNix and the machine's default vault. Do not embed endpoint, account, API-key, or tracker data in Nix source, tests, or documentation. Prowlarr remains responsible for outbound indexer requests; Drlight's Arr apps do not make direct indexer requests unless a user explicitly changes that decision later.

## Existing library and ongoing imports

The organized-library bootstrap is complete, and the local Drlight library is authoritative. The legacy organized-library sync service and timer have been removed. Do not sync the seedbox's organized library into Drlight again.

For new downloads:

1. Drlight Arr apps use Ultra Transmission as their authenticated download client over HTTPS RPC.
2. A Drlight staging job pulls only completed torrent payload files from Transmission's configured completed-download root into `/srv/media/.arr-staging`, on the same ZFS filesystem as the library. It must not use `--delete` or `--remove-source-files`.
3. Arr remote-path mappings translate Transmission's reported seedbox paths to the local staging path. The mapping does not transfer files; the staging job must copy them first.
4. Drlight Arr apps import from local staging into their canonical library roots. They must not move or delete the seedbox source.
5. Do not consider a torrent's seedbox files for cleanup until staging completes successfully and the Arr library has a verified local import for every required media file. Use size-and-mtime checks, not checksums. Any ambiguous path, partial transfer, missing import, or mismatch blocks cleanup.

Keep the staging timer disabled by default until runtime settings and Arr remote-path mappings are populated and tested. The staging job remains copy-only. The report-only cleanup controller is triggered only after a successful staging run and serializes with staging and Arr import verification.

## Retention and cleanup

Cleanup is a separate Drlight systemd service and starts in report-only mode. It may request data deletion only through Transmission's documented torrent-remove-and-local-data RPC after re-fetching current torrent state and passing every gate:

1. The torrent is complete and has accumulated at least 240 actual seeding hours or reached ratio 3.0.
2. Rsync has completed the transfer and the Arr application has imported all associated content locally. Each required local file exists and matches the candidate by the approved size/mtime policy.
3. Every associated private tracker is explicitly classified and its account-wide ratio is known and at least 0.6. Current public trackers need no account-ratio lookup. Unknown/private trackers without a supported ratio source fail closed.
4. No file to be removed is shared with a torrent that is not also eligible. If Transmission data ownership or the download/library path relationship is unclear, retain the seedbox data.

Never delete source data with rsync flags or direct `rm`; never remove a partial torrent; never delete based only on a successful timer tick. A failed sync, missing ZFS mount, unavailable Transmission/Prowlarr/Tailscale state, unverified Arr import, or unknown ratio leaves data untouched. Keep logs to aggregate counts and safe reason codes; do not log media names, paths, announce URLs, passkeys, or credentials.

The pre-existing organized media directories on Ultra.cc may contain separate copies or hardlinks to torrent payloads. Do not assume Transmission's remove operation will reclaim those copies. Inventory their path/inode relationships during migration. Any cleanup of legacy organized-library entries must be a separate, report-only inventory first and must not remove a path still used for seeding. Do not add a broad recursive cleanup rule.

## Credential and data safety

- Use Drlight's OpNix integration with unqualified references resolved through its `Opnix` default vault. Keep the runtime configuration fielded; do not use a JSON configuration blob.
- The `Ultra Media Sync Config` secure note provides separate `host`, `username`, `knownHosts`, `rpcUrl`, and `completedDownloadsRoot` fields. The SSH port defaults to `22` in Nix. No organized-library root or source mapping is needed after the bootstrap; OpNix materializes the required staging values as restricted runtime files.
- The Transmission login must be available in the `Opnix` vault as `Ultra - Transmission/username` and `Ultra - Transmission/password`. Keep the password field unambiguous for the OpNix service account; do not reference the `Homelab` vault from the OpNix service. The existing `Ultra Media Sync Key/private key` remains in `Opnix`.
- Keep Transmission, Arr, Prowlarr, Tailscale, and tracker credentials out of Nix source and the Nix store; do not put secret values in process arguments or logs.
- Transfer application backups over authenticated SSH/Tailscale, store them outside Git with restrictive permissions, and retain rollback copies until the migrated apps pass validation.
- Do not modify Ultra.cc app state, stop old apps, or delete seedbox files as part of build/test validation. Actual cutover and destructive operation require a separate deployment/activation step.

## Fail-safe rollout

1. Preflight read-only discovery must establish app versions, database backup/restore compatibility, remote download paths, Drlight path mappings, Transmission RPC behavior, and Ultra-to-Drlight Tailscale reachability. Report only safe aggregate results; never print media paths or credentials.
2. Run new Drlight services and cleanup in report-only mode. Keep current Ultra.cc services and data available for rollback while comparing library counts and representative import state.
3. Do not enable Transmission data removal until Tailscale connectivity, rsync staging, Arr imports, size/mtime verification, path ownership, and tracker classification have all passed in the deployed environment.
4. Keep destructive cleanup explicitly disabled in Nix configuration during implementation. No deployment or seedbox deletion is part of this design approval.

## Validation

Add automated tests for:

- Drlight-only Arr/Bazarr/Mylar3 services, shared media permissions, library roots, API binding/firewall restrictions, and runtime-only secrets;
- Prowlarr-to-Drlight connectivity requirements and the Ultra Tailscale beta fail-closed behavior;
- rsync staging of completed downloads, path remapping, partial-transfer handling, and the absence of destructive rsync flags;
- migrated app root path settings and Bazarr's connection to local Sonarr/Radarr;
- the 240-hour-OR-3.0 policy, 0.6 private account floor, no-checksum local verification, app-import proof, path/ownership overlap, report-only default, and no-delete failure cases;
- Transmission RPC behavior matching the deployed RPC version before destructive mode can ever be enabled;
- Tailscale-only Arr API reachability from Prowlarr's Ultra app namespace, with no public Arr API exposure;
- Prowlarr's configured indexer proxy/Redirect behavior and the expected indexer egress location.

## References

- [Original Ultra.cc direct-media-sync design](2026-11-04-ultra-media-sync-design.md) (its service-placement and ongoing-mirror assumptions are superseded by this expanded design)
- [Ultra.cc Tailscale application](https://docs.ultra.cc/applications/tailscale) (currently documented as beta)
- [Servarr remote path mappings](https://wiki.servarr.com/en/sonarr/settings)
- [Prowlarr indexer behavior](https://wiki.servarr.com/en/prowlarr/indexers)
- [FlareSolverr troubleshooting](https://github.com/FlareSolverr/FlareSolverr/wiki/Troubleshooting)
- [Transmission RPC specification](https://github.com/transmission/transmission/blob/main/docs/rpc-spec.md)
