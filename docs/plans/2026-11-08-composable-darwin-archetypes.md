# Composable Darwin Machine Archetypes Implementation Plan

> **Note:** Execute this plan task-by-task in the current jj workspace. Follow TDD: add the failing configuration assertions first, run them to observe RED, then implement and rerun for GREEN.

**Goal:** Remove per-machine MegamanX and darwin-server configuration directories while preserving their behavior through explicit catalog-selected Darwin archetypes, and remove Temporal from MegamanX.

**Architecture:** Keep `base-darwin.nix` as the common Darwin foundation imported by each profile. Extract shared telemetry into `server-observability-darwin.nix`, local inference into `headless-inference-darwin.nix`, and Lume VM administration into `vm-management-darwin.nix`. The machine catalog remains the source of host identity, secret profile, node-exporter inventory, `myConfig` overrides, and machine-only module settings.

**Tech Stack:** Nix flakes, nix-darwin modules, catalog-based machine composition, Nix `runCommand` evaluation tests, devenv tasks, jj.

---

## Source of truth and constraints

- Binding design: `docs/superpowers/specs/2026-11-08-darwin-machine-archetypes-design.md`.
- MegamanX's current inference and supporting-tool settings are the reference when shared behavior conflicts with the older generic server profile.
- Temporal is removed from MegamanX completely: no module import, `myConfig.temporal` enablement/UI address, or `temporal-cli` package. Do not create a Temporal archetype.
- Preserve machine-specific differences: MegamanX's password-based SSH exception, restricted `nixbuilder` account/trusted-user configuration, Tailscale daemon keep-alive, service settings, `MegamanX` secret profile, and Opnix-routed sudo-password reference; darwin-server's Lume configuration, opt-in SSH/key-only policy, `Personal` secret profile, and deployment sudo policy.
- Preserve `system.stateVersion`, `system.primaryUser`, all packages/aliases, the `olm` permitted insecure package, and node-exporter catalog metadata.
- Do not modify `wweaver` behavior or change external machines/services. No live switch or deployment.
- Every implementation behavior change below starts with a failing test and observed RED.

## Task 1 — Specify the desired catalog-only server configurations in tests

**Files:**
- Modify: `tests/test-phase4-darwin-server.nix`
- Modify: `tests/default.nix` only if the test needs additional inputs (the check is already registered there).

**Step 1: Extend the existing evaluated Darwin regression test.**

Add assertions that:

- `catalog.MegamanX.modules` selects `headless-inference-darwin.nix` and does not import a per-machine `hosts/` or `machines/` module.
- `catalog.darwin-server.modules` selects `vm-management-darwin.nix` and does not import a per-machine `hosts/` or `machines/` module.
- Neither host directory exists after migration.
- MegamanX retains oMLX, Bifrost, SearXNG, Caddy, Pi, Zellij, Tailscale, Vector, node exporter, the Opnix vault and existing credentials/settings, but has no Temporal option enabled, Temporal daemon, or `temporal-cli` system package.
- darwin-server retains Lume, developer/OpenCode management roles, Vector, node exporter, `stateVersion = 4`, `primaryUser = "monkey"`, and no inference services.
- `wweaver` continues to evaluate using the workstation profile and shared base.

Update the current Temporal-positive assertions in this test to the required Temporal-absent assertions.

**Step 2: Run the focused check and confirm RED.**

```sh
nix build ".#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).phase4-darwin-server" --no-link
```

Expected: failure because the current catalog composition still imports per-machine `machines/` modules and MegamanX currently enables Temporal.

## Task 2 — Implement and evaluate the reusable Darwin archetypes

**Files:**
- Create: `library/archetypes/server-observability-darwin.nix`
- Create: `library/archetypes/headless-inference-darwin.nix`
- Create: `library/archetypes/vm-management-darwin.nix`
- Modify: `library/archetypes/workstation-darwin.nix` only if needed to make its shared-base import explicit and singular.
- Remove after consumers are migrated: `library/archetypes/headless-omlx-darwin.nix`, `library/archetypes/headless-server-darwin.nix`.

**Step 1: Implement shared server observability.**

Create a focused archetype that imports the Darwin Vector and node-exporter service modules, enables Vector, and defaults the collector destination to `drlight`. Do not set node-exporter enablement or identity here; the catalog inventory continues to control that. Host labels and log globs remain in catalog overrides.

**Step 2: Implement the inference profile.**

Create `headless-inference-darwin.nix` importing `base-darwin.nix`, `server-observability-darwin.nix`, the Darwin oMLX/Bifrost/SearXNG/Caddy modules, Ghostty terminfo, and the existing nix-homebrew module if required to preserve current MegamanX evaluation. Put reusable inference-role defaults here (Pi and Zellij) and keep model/port/cache/provider/credentials/SSH values in the machine catalog. Do not import Temporal.

**Step 3: Implement the VM-management profile.**

Create `vm-management-darwin.nix` importing `base-darwin.nix`, `server-observability-darwin.nix`, the Lume module, and the existing VM management defaults: developer/OpenCode roles, RTK, image pre-pull/auto-update, management packages, timezone, SSH hardening when opted in, and passwordless deployment sudo. Do not import or enable inference services.

**Step 4: Run the focused test to confirm GREEN for the profile-level behavior.**

Re-run `phase4-darwin-server`. Resolve module option conflicts and evaluation failures before catalog migration. Do not weaken the assertions to make the test pass.

## Task 3 — Move both machines into catalog composition and remove Temporal

**Files:**
- Modify: `library/machines/catalog.nix`
- Delete any remaining per-machine modules and directories for MegamanX and darwin-server under `hosts/` or `machines/`.
- Remove superseded archetypes listed in Task 2.
- Modify: `docs/plans/2026-11-06-megamanx-deploy-192-168-1-81.md` to remove stale host-path and Temporal deployment instructions.
- Regenerate: `docs/reference/options.md` after Temporal is no longer present in the active Darwin configuration options.

**Step 1: Replace darwin-server's host module with its archetypes.**

Select the VM-management profile in `catalog.darwin-server.modules`; keep its permitted insecure-package module. Move `mkUser "monkey" "me@willweaver.dev"` output and the existing superpowers/OpenCode values to `overrides`. Preserve state version and primary user in a small inline machine module. Remove the unneeded `mkUser` special argument if nothing else in the entry consumes it.

**Step 2: Replace MegamanX's machine module with its archetype.**

Select the inference profile in `catalog.MegamanX.modules`. Move the full existing `mkUser` result and MegamanX-specific `myConfig` values into `overrides`, using `import ../lib/mk-user.nix` in the catalog. Keep state version and primary user, Tailscale service keep-alive, password SSH override including the restricted `nixbuilder` Match block, trusted-user configuration, builder account/key, packages, and shell aliases in a small inline module. Use the unqualified `MegamanX Sudo Password/password` reference so shared `devenv` tasks resolve it through MegamanX's `Opnix` default vault. Keep `secretProfile = "MegamanX"` and `nodeExporter.enable = true` in the catalog. Keep the `mkUser` special argument required by the Darwin catalog constructor and other Darwin machine modules.

Remove the Temporal service module from the catalog module list and remove Temporal enablement/UI addresses and `temporal-cli` from MegamanX settings/packages. Do not alter any other machine's Temporal configuration. Preserve the existing restricted `nixbuilder` account, its authorized key, trusted-user settings, and key-only `Match` block while relocating the machine module into the catalog. Update the active MegamanX deployment plan to reflect its catalog/archetype composition and the absence of Temporal; document its Opnix default-vault sudo-password reference. Regenerate the options reference with `devenv tasks run docs:generate-options` and verify the Temporal option section disappears only because it is no longer part of any active machine configuration.

**Step 3: Run the focused regression test to confirm GREEN.**

```sh
nix build ".#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).phase4-darwin-server" --no-link
```

Then run the related node-exporter and catalog checks:

```sh
nix build ".#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).type-server-archetypes" ".#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).machines-inventory" ".#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).observability-inventory" --no-link
```

## Task 4 — Record implementation decisions as ADRs

**Files:**
- Create: `docs/adr/0001-darwin-machine-composition.md`
- Create: `docs/adr/0002-darwin-server-capability-boundaries.md`

Record the final decisions made during implementation, including:

1. Functional Darwin profiles import the shared base via Nix `imports`; the machine builder does not inject it.
2. Inference, VM management, and server observability are separate capabilities; Temporal is not part of MegamanX.
3. Machine-specific settings stay in the catalog; MegamanX's SSH password exception remains host-scoped; its current values win over older shared defaults only where they represent intended shared inference behavior.

Include context, decision, consequences, and status. Mark them for post-implementation review. Do not claim an ADR was accepted until the implementation review is complete.

## Task 5 — Validate and review the completed change

**Files:**
- Any implementation/test files required by the full checks.
- ADR files from Task 4.

Run:

```sh
devenv tasks run check:lint
devenv tasks run test:build-checks
devenv tasks run test:eval
```

Also evaluate both native Darwin configurations and inspect their resolved settings. Review every ADR against the final archetype imports/catalog values and update it if the implementation differs from the decision. Confirm tests assert behavior rather than only matching source comments. Report any unavailable cross-platform validation honestly. Do not run a switch or alter a machine outside this repository.
