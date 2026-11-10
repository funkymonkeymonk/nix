# ADR 0003: Reconcile Media Application Configuration Declaratively

**Status:** Proposed; implementation is available for review  
**Date:** 2026-11-10

## Context

The Drlight media-management change provisions Radarr, Sonarr, Lidarr, Bazarr, and Mylar3 as native NixOS services. NixOS can declaratively manage service lifecycle and some startup settings, but several important application settings live in each application's database and are normally changed through its API or UI. Leaving those settings to manual UI configuration makes a migrated deployment hard to reproduce and allows it to drift from Nix.

The machine also uses a remote Transmission service on Ultra. Its RPC credentials and download paths are runtime data, while the local Arr applications must import only files staged on Drlight. Existing migrated application databases must remain available and must not be replaced or broadly pruned as part of configuration reconciliation.

## Decision

1. Use native NixOS service options for service lifecycle, ports, binding, filesystem access, and settings the service module explicitly supports. Use runtime secret files for secret-valued settings; never put credentials in Nix-store-backed settings.
2. Manage application-database settings through idempotent API reconciliation services. Represent desired state in Nix, wait for each application API to become available, and reconcile only the resources declared as managed.
3. The initial managed Arr resources are named download clients, local library root folders, and remote path mappings for Radarr, Sonarr, and Lidarr. The remote Transmission endpoint is derived from runtime secret files. The mapping points from the seedbox-reported completed-download root to Drlight's local staging path; it does not perform file transfer.
4. Manage Bazarr's connections to the Drlight-local Sonarr and Radarr APIs through its API. Keep app-specific adapters separate from the common reconciliation primitives because the applications have different API contracts.
5. Manage Mylar3's supported startup settings through a typed service option and a runtime-generated configuration file, rather than mutating its database or assuming it implements the Servarr API. The live service uses the watch-folder downloader with torrent download/search disabled; preserve that mode and do not connect Mylar3 directly to remote Transmission.
6. Reconciliation is additive/update-only by default. It may create a missing declared object or update the matching object, but it does not delete undeclared app settings, root folders, download clients, profiles, comics, or indexers. Migrated user data is preserved.
7. The local Drlight module does not configure the remote Prowlarr service. Prowlarr remains owned by its Ultra deployment. Its remote app connections remain a separately managed deployment boundary.
8. Application profiles, custom formats, language/provider choices, and catalog contents are user policy. Do not invent or overwrite these from defaults during migration. Preserve them through application-native backup/restore until their exact desired values are explicitly declared; the reconciliation pattern must support adding such adapters later.
9. Ultra's Arr and Mylar3 URL bases are reverse-proxy prefixes. Drlight exposes the services on private Tailscale ports instead, so clear Arr `server.urlbase` and set Mylar3 `HTTP_ROOT` to `/`. Preserve Forms authentication. Arr updates use the Nix package/update lifecycle (`external`), not the seedbox's Docker updater.
10. The current Bazarr configuration stores Sonarr/Radarr connection credentials but leaves both integrations disabled. Reconcile the local endpoints and keys while preserving those disabled flags by default. Do not activate subtitle processing or invent language/provider policy during migration.

## Consequences

- Nix becomes the source of truth for declared integration resources while each application's database continues to own unmodeled migrated data.
- Applying a NixOS generation can repair drift in managed resources without erasing unrelated UI configuration.
- API keys and Transmission credentials remain runtime-only. Reconciliation fails closed if an app is unavailable, its API key cannot be read, a resource identity is ambiguous, or a secret file is missing.
- Every adapter needs contract tests for its API payload and behavior. Generic HTTP code must not guess service-specific semantics.
- Application-native backups carry the existing profiles, custom formats, indexers, providers, and catalog state across the host migration; Nix does not re-create those opaque database records.
- The initial API layer manages integration endpoints and root-folder entries, not every value in each app database. Existing item paths still require the documented, verified cutover remap to local library paths; ensuring a new root-folder entry alone does not remap existing series or movies.
- Bazarr connections are configured but remain inactive unless the declared `useSonarr`/`useRadarr` options are explicitly enabled.

## Review checklist

- [ ] No secret value is included in a Nix derivation, command line, or ordinary log.
- [ ] The managed state is idempotent and updates only uniquely identified declared resources.
- [ ] No deletion is performed by the default reconciliation path.
- [ ] Arr mappings point to local staging and are distinct from the staging transfer itself.
- [ ] Bazarr and Mylar3 use their own supported interfaces.
- [ ] Existing migrated app databases and catalog data remain untouched outside declared resources.
