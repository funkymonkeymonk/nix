# Composable Darwin Machine Archetypes Design

**Status:** Approved; implemented and reviewed  
**Date:** 2026-11-08

## Goal

Remove the per-machine `hosts/darwin-server/` and `hosts/megamanx/` configuration layers, as well as the equivalent `machines/` directories created by the newer catalog migration. Keep both machines in `library/machines/catalog.nix`, where their selected Darwin archetypes and host-specific values are visible. Establish one shared Darwin base that workstation and server archetypes reuse, then separate VM management from local inference services.

Use MegamanX's current configuration as the more up-to-date reference when shared behavior conflicts. Remove Temporal from MegamanX entirely; do not create a Temporal bundle as part of this change.

## Design

### Composition model

Do not inject a Darwin base from the machine builder. Reusable Darwin profiles import `library/archetypes/base-darwin.nix` through their `imports`, preserving the repository's existing Nix module composition model. Keep the base limited to shared Darwin plumbing: common modules, Darwin defaults, Home Manager and Opnix integration, SSH public-key installation, and default SSH enablement behavior. Do not put server-only services, workstation roles, or optional telemetry in the base.

Keep `workstation-darwin.nix` as the workstation profile that reuses the shared base. Add `headless-inference-darwin.nix` and `vm-management-darwin.nix` as focused server profiles for inference and VM management. Each profile explicitly imports the shared base; both server profiles also import the server-observability archetype. The catalog selects the appropriate profile for each machine; it does not need a host-directory import for either server.

### Inference-server profile

Add a focused headless inference Darwin archetype. It owns the service-module imports and reusable enablement for MegamanX's local inference stack and its supporting tools:

- oMLX
- Bifrost
- SearXNG
- Caddy
- Pi and Zellij integration for operating the inference host

Temporal is excluded from the archetype and from MegamanX. Host-specific values such as model names, ports, cache sizing, log globs, labels, endpoints, 1Password item names, and SSH policy remain in the MegamanX catalog entry. Use MegamanX's current values as the source of truth where the older generic server profile has conflicting shared behavior.

### VM-management profile

Add a focused headless VM-management Darwin archetype for the existing `darwin-server` machine. It owns the Lume service module and defaults, VM-management developer/OpenCode roles, and their basic management tools. It must not enable the inference stack. Preserve the current VM image pre-pull/auto-update behavior and server-specific SSH/sudo policy where that policy is part of the VM-management capability.

### Server observability

Keep server telemetry out of the Darwin base. Add `server-observability-darwin.nix` to import the shared Vector and node-exporter service modules, and compose it with both server profiles. Keep node-exporter enablement and inventory identity in the machine catalog; the existing inventory module remains the source of its enabled state and port. Keep Vector labels and log paths as machine-level configuration; use the shared `drlight` collector destination for these server profiles.

### Machine-specific configuration

Move each host's `myConfig` from its deleted `default.nix` into that machine's catalog `overrides`, using the existing `mkUser` helper to preserve user defaults. Put non-`myConfig` machine settings into a small inline catalog module or a focused archetype only when they express reusable behavior. Keep machine identity, secret profile, hostname, platform, and node-exporter metadata in the catalog.

For MegamanX, preserve its explicit Tailscale enablement, Tailscale daemon keep-alive, password-based SSH exception, restricted `nixbuilder` account and trusted-user configuration, server package list, and shell aliases. The password SSH exception remains specific to MegamanX; the `nixbuilder` account remains public-key-only with the forced Nix daemon command; neither policy may weaken the VM-management profile's SSH policy. For `darwin-server`, preserve its current SSH opt-in behavior and key-only authentication policy if SSH is enabled, along with Lume behavior and passwordless deploy sudo policy. Preserve each machine's `system.stateVersion` and `system.primaryUser` in its catalog module configuration. Keep MegamanX's `Opnix` default vault. Its sudo-password reference is unqualified so shared `devenv` tasks resolve it through that default vault; keep the password item in `Opnix`. Do not make MegamanX's secret profile or service credentials defaults for other machines.

## Migration scope

1. Keep `base-darwin.nix` as the sole shared Darwin foundation and keep the workstation profile using it.
2. Add `headless-inference-darwin.nix`, `vm-management-darwin.nix`, and `server-observability-darwin.nix`; remove the superseded `headless-omlx-darwin.nix` and `headless-server-darwin.nix` after confirming no remaining consumers.
3. Replace the two host-directory imports in the catalog with archetype imports and move their machine-specific configuration into catalog overrides/modules.
4. Remove the Temporal module import and configuration from MegamanX.
5. Delete any remaining `hosts/megamanx/` and `hosts/darwin-server/` modules and the newer `machines/megamanx/` and `machines/darwin-server/` modules/directories.
6. Do not change `wweaver` or unrelated NixOS machine composition except as required by shared Darwin option evaluation.

## Acceptance criteria

- Both server machines are fully described by catalog entries and reusable archetypes; neither catalog entry imports per-machine modules from `hosts/` or `machines/`.
- The Darwin base remains reusable by workstation and server profiles; each profile imports it through the Nix module `imports` mechanism, not via builder auto-injection.
- MegamanX enables its existing inference services and supporting tools but has no Temporal module import, Temporal enablement, or Temporal UI configuration.
- `darwin-server` retains VM-management behavior without acquiring the inference stack.
- Shared inference behavior follows the current MegamanX configuration; host-specific security, identity, and secret values remain machine-specific.
- Node-exporter inventory behavior remains controlled by catalog metadata.
- Add or update automated checks to cover catalog composition, retained service/configuration behavior, absence of Temporal on MegamanX, and absence of the two host-directory imports.

## Validation

Run `devenv tasks run check:lint` and `devenv tasks run test:build-checks`. Run Darwin evaluation checks for the changed catalog systems when available. Confirm targeted tests fail before implementation changes and pass afterward, following the repository's TDD requirements.
