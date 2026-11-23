# Declarative Prowlarr App Connections Design

**Status:** Draft; awaiting user approval  
**Date:** 2026-11-22

## Intent

Make Drlight's connections to the existing Prowlarr instance declarative in
this Nix repository. Prowlarr remains on the seedbox and remains the source of
the configured indexer catalog. Nix will own Prowlarr's application targets
for Drlight Radarr, Sonarr, and Lidarr, so Prowlarr can synchronize its
configured indexers to those apps.

The user wants seedbox connection details kept out of Git and private
configuration stored in the machine's default 1Password vault. This is a
configuration-only change; it does not authorize deployment or changes to the
live seedbox.

## Goals

- Declare and reconcile one Prowlarr application target for each of Drlight's
  Radarr, Sonarr, and Lidarr services.
- Keep Prowlarr on the seedbox and use its normal app-sync mechanism rather
  than adding indexer feed records independently to every Arr app.
- Keep Prowlarr's URL/API key and private Arr target URLs in runtime secrets
  materialized by Opnix from the Drlight machine's default 1Password vault.
- Read each local Arr API key from that Arr's runtime configuration and expose
  it only through a restricted runtime file. Do not duplicate generated local
  keys in Git, the Nix store, command-line arguments, or logs.
- Use private networking only. Do not open public Prowlarr or Arr API ports or
  add a public-proxy fallback. Fail closed when secrets, API schemas, or
  private connectivity are unavailable.
- Make reconciliation additive/update-only: update only uniquely identified
  Drlight targets, preserve unrelated fields and existing seedbox app targets,
  and never delete Prowlarr application or indexer records.
- Do not put seedbox hostnames, addresses, URLs, credentials, tracker names,
  or tracker data into Nix source, tests, or documentation. Source may contain
  only unqualified 1Password item/field references and runtime file paths.

## Non-goals and legal boundary

- Do not install, move, or manage the lifecycle of Prowlarr or FlareSolverr;
  they remain owned by the seedbox deployment.
- Do not add, edit, remove, or otherwise reconcile Prowlarr's indexer/tracker
  definitions, proxy/redirect settings, or credentials.
- Do not configure Mylar3 or Bazarr in this change. Mylar3 uses a separate
  application configuration path; this design scopes “the Arrs” to Radarr,
  Sonarr, and Lidarr.
- Do not trigger searches, downloads, torrent changes, or seedbox cleanup from
  the reconciler. Prowlarr may synchronize its already-configured indexers to
  the new targets, and the Arr apps may use them according to their normal
  behavior; review the existing Prowlarr configuration before enabling the
  integration.
- Nix cannot determine whether a source or item is lawful. The operator is
  responsible for using only indexers, accounts, and content they are
  authorized to access under applicable law and service terms.
- Do not apply the Nix generation, contact live Prowlarr/Arr APIs, or modify
  1Password as part of implementation or build tests.

## Approaches considered

1. **Nix reconciles Prowlarr application targets (chosen).** A Drlight
   systemd oneshot calls Prowlarr's supported API and ensures the three Drlight
   app targets exist. Prowlarr remains the indexer source of truth and performs
   its normal synchronization. This gives Nix ownership of the requested
   connections without copying the indexer catalog into Nix.
2. **Nix adds Prowlarr feeds directly in each Arr app.** Prowlarr documents
   RSS-compatible feeds per indexer, rather than one universal Arr-side
   connection. This would require maintaining or dynamically discovering every
   indexer in each app, duplicating the catalog and risking duplicate or stale
   entries. It does not match the selected central-source-of-truth model.
3. **Keep Prowlarr targets operator-managed in its UI.** This preserves the
   existing boundary but does not meet the request to manage the integration
   in Nix.

## Design

### Ownership and data flow

- Nix declares the desired Drlight target identity, service type, endpoint
  secret-file path, and Arr API-key runtime-file path for Radarr, Sonarr, and
  Lidarr.
- A Drlight systemd oneshot reads the Prowlarr API URL and key at runtime,
  reads the three local Arr API keys from their protected runtime files, and
  uses Prowlarr's supported application API to create a missing target or
  update the declared connection fields on a uniquely matching target.
- Prowlarr then synchronizes its own configured indexers to the targets. Nix
  does not reproduce indexer definitions or take ownership of indexer
  selection.
- The service must use the API schema exposed by the running Prowlarr version
  (or another version-verified contract) rather than inventing resource fields.
  Preserve server-generated IDs and all fields not owned by this design. If a
  required field/schema is unsupported or a managed identity is ambiguous,
  stop without mutation and log only a safe failure reason.

### Secrets and network boundaries

- Use unqualified Opnix item/field references so the shared helper resolves
  them from `myConfig.onepassword.defaultVault` (Drlight currently selects
  `Opnix`). The proposed single item is `Prowlarr Drlight Integration`, with
  fields `prowlarrUrl`, `prowlarrApiKey`, `radarrUrl`, `sonarrUrl`, and
  `lidarrUrl`. These are references only; their values must never appear in
  Git. At minimum, runtime secrets must supply the remote Prowlarr URL,
  Prowlarr API key, and private target URLs for Radarr, Sonarr, and Lidarr.
- If any needed item is outside the default vault, stop and ask the user to
  move it or explicitly change the machine's default vault; do not add a
  cross-vault exception.
- Keep secret values out of Nix-generated JSON and command arguments. Store
  only runtime file paths in the Nix store. Do not emit request URLs containing
  credentials, API headers, response bodies containing secrets, or endpoint
  values in logs.
- Arr API keys are generated by the local apps and remain app-owned. Extract
  them from their local configuration into restrictive runtime files and
  grant the reconciler only the read permissions it needs. Do not copy these
  generated keys into 1Password, which would create a second source of truth
  and rotation drift.
- The Drlight-to-Prowlarr management API route and Prowlarr-to-Drlight Arr API
  routes must both work over the approved private network. The current Ultra
  Tailscale integration is documented as beta, so prove both directions in
  the deployment preflight. No public port, public proxy, or direct-indexer
  bypass is an acceptable fallback.
- Do not change Drlight's existing firewall exposure as part of this feature;
  add no new allowed ports. Verify that no Arr or Prowlarr API is reachable
  from the public internet before enabling the live integration.

### Reconciliation behavior

- Give each managed target a stable, explicit identity distinct from any
  existing seedbox target: `Drlight Radarr`, `Drlight Sonarr`, and
  `Drlight Lidarr`. Match only by exact name plus app implementation. Create
  when absent; update only a unique exact match; fail on duplicates. Do not
  adopt a different target merely because its endpoint happens to match.
- On each run, fetch the current application list and the schema needed to
  construct the relevant app types. Create a missing target; update only its
  declared connection fields when exactly one target matches; leave unrelated
  resources untouched. Never issue a delete request.
- Declare the Prowlarr sync policy explicitly in Nix. Use Full Sync so
  Prowlarr remains the source of truth for indexer definitions in these three
  Arr apps; this means Prowlarr can overwrite local edits to synced indexers
  and remove synced entries when they are removed from Prowlarr. The
  reconciler itself never deletes Prowlarr application or indexer records and
  does not change any indexer definition in Prowlarr. Make the sync consequence
  explicit in the migration guide and require review of the existing Prowlarr
  indexer catalog before deployment.
- Reconciliation must be idempotent. A no-op run must not write to the API.
- The service is opt-in at the module level and enabled only on Drlight. It
  runs after Opnix and the local Arr API-key extraction units, retries boundedly
  while the private API is unavailable, and fails without mutating state if
  credentials or connectivity are missing.

### Tests and documentation

- Unit-test the adapter with an in-process HTTP server: schema handling,
  resource identity, create/update/no-op behavior, preservation of unrelated
  fields, ambiguous matches, API errors, missing secrets, and proof that no
  delete request is issued.
- Verify tests never use live seedbox endpoints or real credentials and that
  failures/logs do not disclose secret values.
- Add Nix evaluation assertions for the Drlight opt-in, target types, secret
  references/file paths, service ordering, least-privilege groups, and absence
  of new firewall ports.
- Update the API-reconciliation explanation and media migration runbook to
  replace only the manual Prowlarr app-connection step. Keep live private-route
  verification and indexer/redirect review as deployment preconditions.

## Constraints and remaining implementation choices

- No live seedbox or 1Password access is available to implementation tests.
- Exact Prowlarr API schema/resource fields and supported sync policy must be
  verified against the API contract before writing the adapter. The builder
  may choose the narrowest compatible API sequence while preserving the
  ownership and no-delete guarantees above.
- The user must provide the required unqualified 1Password item/field
  fields (proposed item/fields are listed above) in Drlight's default vault
  before live deployment. This design does not assume that the item exists or
  modify 1Password. If the existing values are in another vault, they must be
  moved to `Opnix` before the module references them.
