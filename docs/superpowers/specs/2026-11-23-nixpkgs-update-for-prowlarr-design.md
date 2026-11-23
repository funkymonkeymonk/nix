# Shared Nixpkgs Update for Prowlarr Restore Compatibility

**Status:** Proposed for user approval  
**Date:** 2026-11-23

## Intent

Move the repository's shared Nixpkgs input forward so the Drlight-managed Prowlarr package is at least as new as the seedbox's Prowlarr `3.0.2.5780`. The current locked package is `2.6.5.5623`, and restoring a newer native backup into it is not safe.

## Decision

Update the existing shared `nixpkgs` flake input to a revision that packages Prowlarr `3.0.2.5780` (or newer). Synchronize `devenv.yaml` and `devenv.lock` with the shared revision as required by the repository's machine-inventory check, while leaving the separate Devenv CLI input at its pinned stable release. Do not add a second package-specific nixpkgs input or local package override. The current nixpkgs unstable package recipe already contains `3.0.2.5780` and uses .NET 10.

## Scope and validation

- The lockfile update affects package evaluation for all systems in the repository, even though only Drlight will be deployed in this operation.
- Verify Drlight's evaluated Prowlarr version is at least `3.0.2.5780`.
- Run repository lint, build checks, and NixOS/Darwin evaluation as supported on this host.
- Generate and inspect a new single-machine Drlight Machines plan after the lockfile update. Apply only that reviewed plan; do not deploy other catalog machines.
- Keep OnePacerr disabled. Do not restore the Prowlarr backup or cut over from Ultra until the native backup is created, version compatibility is checked, and Prowlarr runtime proxy/app settings are ready.

## Alternatives considered

- Add a package-scoped Nixpkgs pin/overlay: less impact on unrelated packages, but the user requested updating the shared system package set instead.
- Restore the `3.0.2.5780` backup into Drlight's current `2.6.5.5623`: rejected because it would downgrade the application database.
