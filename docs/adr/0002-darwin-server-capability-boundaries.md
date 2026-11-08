# ADR 0002: Separate Darwin Server Capabilities and Host Policy

**Status:** Accepted; reviewed after implementation  
**Date:** 2026-11-08

## Context

`darwin-server` and MegamanX had overlapping telemetry and headless-server setup, but their main workloads differ. One manages macOS virtual machines with Lume; the other runs local inference services. Combining both workloads into one server archetype couples unrelated services and makes catalog-only machine configuration difficult. MegamanX's inference configuration is newer and should win when shared inference behavior conflicts with the older generic server setup.

## Decision

Use three focused server archetypes:

- `server-observability-darwin.nix` provides Vector and node-exporter module availability and the shared collector destination. Catalog metadata remains authoritative for whether a node exporter is enabled and its inventory identity.
- `headless-inference-darwin.nix` provides the inference service modules and shared Pi/Zellij support for oMLX, Bifrost, SearXNG, and Caddy. Temporal is not part of MegamanX's composition, and no Temporal archetype is introduced.
- `vm-management-darwin.nix` provides Lume and its VM-management developer/OpenCode tooling and policy.

Machine identity, secret profile, user defaults, workload tuning, log labels/paths, Tailscale and SSH exceptions, the restricted `nixbuilder` account, and other host-specific values remain in catalog metadata, overrides, or inline machine modules. Use MegamanX's current configuration as the source of truth for shared inference behavior, but do not generalize its password-based SSH exception, builder account, or secret settings to other machines.

## Consequences

- Both server targets retain their distinct workloads without depending on per-machine modules under `hosts/` or `machines/`.
- MegamanX has no Temporal service, Temporal UI configuration, or `temporal-cli` package.
- The observability module bundle can be reused without making telemetry part of the workstation base.
- Catalog entries are more explicit but include some machine-specific inline module data that is not itself reusable.

## Post-implementation review

The catalog selects the inference and VM-management profiles directly. Both reuse the shared observability archetype. MegamanX retains its current service settings, password-auth SSH exception, and restricted key-only Nix builder account; `darwin-server` retains Lume, opt-in/key-only SSH behavior, and deployment sudo. Temporal was removed from MegamanX's module set, configuration, and package list. The Darwin evaluation and regression checks were run after these changes.
