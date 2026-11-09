# ADR 0001: Compose Darwin Profiles Through Nix Module Imports

**Status:** Accepted; reviewed after implementation  
**Date:** 2026-11-08

## Context

Darwin machines shared a `base-darwin.nix` module, but server behavior was split between machine directories and broad headless profiles. We want workstation and server profiles to reuse one Darwin foundation while the catalog makes each machine's selected capabilities visible. The machine builder already has a catalog-driven projection path and should not silently inject host policy.

## Decision

Keep `base-darwin.nix` as the shared Darwin foundation. Darwin capability/profile archetypes import it through the normal Nix module `imports` mechanism. The machine builder does not inject it automatically. `workstation-darwin.nix`, `headless-inference-darwin.nix`, and `vm-management-darwin.nix` reuse that foundation.

## Consequences

- Common Darwin modules, Home Manager/Opnix integration, SSH public-key setup, and SSH enablement defaults remain centralized.
- The selected capability profile is visible from each catalog record.
- Server-only behavior does not leak into the shared base or workstation profile.
- A future Darwin profile must import the shared base explicitly, directly or through a composed profile.

## Post-implementation review

The implementation keeps the base import in the workstation profile and imports the same base from both server profiles. `library/machines/flake-parts.nix` and the machine projection logic remain unchanged; there is no automatic builder-level base injection. This matches the decision.
