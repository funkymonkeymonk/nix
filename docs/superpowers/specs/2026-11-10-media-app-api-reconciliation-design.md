# Declarative Media Application Reconciliation Design

**Status:** Approved for autonomous implementation; decisions recorded for later review  
**Related ADR:** [ADR 0003](../../adr/0003-declarative-media-app-reconciliation.md)  
**Parent change:** PR #545, move media management to Drlight

## Goal

Make migration-critical configuration for Drlight's Radarr, Sonarr, Lidarr, Bazarr, and Mylar3 reproducible from Nix while preserving migrated application state and secrets. Establish a reusable API reconciliation pattern for future services whose configuration is stored in an application database rather than native NixOS options.

## Scope and constraints

The implementation owns only the desired state explicitly declared in Nix:

- Radarr, Sonarr, and Lidarr each receive the remote Transmission download-client connection, a mapping from the seedbox-reported completed-download root to `/srv/media/.arr-staging`, and their local library root.
- Bazarr receives its Drlight-local Sonarr and Radarr connection settings.
- Mylar3 receives declarative supported startup settings using its INI configuration mechanism, with the local comics directory and runtime-only credentials where applicable.
- Native NixOS service settings remain the authority for process-level configuration such as ports, binding, authentication policy, and filesystem permissions.

No profile, custom-format, language, indexer, series/movie/comic catalog, or history data is guessed or pruned. Existing migrated databases remain intact. Prowlarr stays on Ultra and is not mutated by a Drlight service. Transmission file transfer remains the responsibility of the existing download-staging unit; API reconciliation only configures client/path metadata.

## Architecture

### Layer 1: service modules

Use `services.radarr`, `services.sonarr`, and `services.lidarr` options for supported static settings. Keep secret values in runtime files supplied by Opnix or application state, not in Nix-store-backed `settings` values. Keep service ownership, writable directories, and interface firewall policy in the existing media-management module.

### Layer 2: common reconciliation primitives and adapters

Add a small internal Python API client/reconciliation library using the standard library. It reads a Nix-generated JSON desired-state file whose secret values are represented only as absolute runtime file references. The common layer handles HTTP requests, bounded timeouts, safe errors, JSON parsing, resource identity checks, and secret-file expansion. App adapters define API versions, routes, desired resource schemas, and update behavior. Do not assume different applications share API contracts.

For Servarr apps, the adapter:

1. reads the API key from the application's runtime `config.xml`;
2. obtains the installed API's download-client schema;
3. creates a missing uniquely named Transmission client from that schema, or updates only the requested fields on the uniquely matching client;
4. ensures the declared local root folder exists; and
5. creates or updates the exact host/remote-path mapping.

The Transmission host, port, URL base, and TLS flag are derived at runtime from the existing secret RPC URL. The RPC username/password and completed-download root are read from their existing runtime secret files. Only credentials are secret; no credential value is serialized into Nix or logged. Each app's Transmission download-client category is distinct.

For Bazarr, a separate adapter follows its own API: read its API key and the local Arr API keys at runtime, then update the Sonarr/Radarr connection settings. It preserves Bazarr settings not owned by this module.

For Mylar3, do not pretend its API is a Servarr API. Add typed settings to the custom NixOS module and produce a runtime INI file using the upstream config option names. Preserve any mutable state/database. Secrets are injected only into the runtime file and the configured file permissions restrict access.

### Reconciliation and failure policy

- Repeating a successful reconciliation with no desired-state change is a no-op.
- Create only when no matching resource exists; update only when exactly one resource matches. Ambiguous identities fail without mutation.
- Preserve server-provided IDs and all unmanaged fields when updating an object.
- Do not delete resources absent from Nix. Destructive pruning is explicitly out of scope.
- Missing config files, API keys, secrets, unsupported schemas, network errors, or API errors fail the oneshot service with a redacted message. They must not trigger fallback to a public endpoint or broaden firewall access.
- A systemd oneshot runs after the service is healthy and before related import/staging use. It can be manually started for inspection; it does not contact Ultra's app UI or change seedbox state.

## Public configuration shape

Keep host-specific desired state in `modules/nixos/media-management.nix` or a narrow adjacent module. Prefer explicit app fields (root, client, mappings, Bazarr connections, Mylar3 settings) over an untyped arbitrary API request list. The shared reconciler is an internal implementation detail. Runtime secret file paths are provided by existing Opnix secrets and the existing staging configuration; no secret item is added without verifying it is in Drlight's default vault.

## Testing

- Python unit tests use an in-process HTTP server and temporary secret/config files. Test API-key extraction, schema-driven create/update, preservation of unmanaged fields, duplicate identity failure, no delete calls, URL derivation, and redaction.
- Bazarr adapter tests verify only the two declared service connections are changed and secret values do not appear in error output.
- Mylar3 config-generation tests verify supported INI keys, local root, runtime-only secret substitution, and restrictive permissions.
- Nix eval tests verify each API sync unit is connected to its app service, declared resource paths match the staged/local roots, no public firewall/Caddy exposure is added, and no secret value is present in derivation text.
- Existing Drlight storage, network-boundary, and migration tests remain in force. No live deployment or calls to seedbox APIs are part of build validation.

## Rollout

The Nix generation can provision services and declare desired integration state without deleting app data. During cutover, restore the native app backups, apply the Nix generation, then inspect each sync service and verify the app API state before enabling recurring staging. Keep runbook steps for the remote Prowlarr/Tailscale integration separate because Prowlarr is outside this host's configuration boundary.
