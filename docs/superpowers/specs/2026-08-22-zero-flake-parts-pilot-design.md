---
title: "Wire flake-parts via a zero-only pilot"
description: "Design for retiring the zero/zero-v2 split and wiring flake-parts into flake.nix, scoped to a single-machine pilot"
type: explanation
audience: agent
last-reviewed: 2026-08-22
---

# Wire flake-parts via a zero-only pilot

## Context

Yak: "Retire zero/zero-v2 split — migrate zero to flake-parts composite
system" (child of "Flake decomposition: Phase 8 — cleanup").

Investigation before design found most of the yak's original acceptance
criteria are already satisfied by prior work (PR #402, "standardize all
hosts on archetypes for flake-parts migration"):

- `zero-v2` is already retired — `tests/test-phase3-zero.nix` asserts it's
  gone.
- `zero` already uses `library/archetypes/desktop-nixos.nix` and the
  correct hardware-specific disk config (`disk-configs/zero.nix`), not the
  generic `single-disk-ext4.nix` stub.
- opnix is already wired at both system and home-manager level via
  `library/lib/mk-system.nix`'s `mkNixosSystem`, used by every NixOS host
  including zero.
- `autoUpgrade.flakeUrl` already points to `github:funkymonkeymonk/nix#zero`
  — no `-v2` suffix.

What's genuinely unstarted: `flake-parts` is declared as a flake input but
never invoked. `flake.nix`'s `outputs` is a plain function, not
`flake-parts.lib.mkFlake`. `library/flake-module.nix` exists but nothing
imports it. The parent yak ("Flake decomposition: Phase 8 — cleanup")
flags this as its own sub-goal (8.3) and says this yak "can pioneer that
wiring if 8.3 hasn't started" — confirmed no separate 8.3 yak exists or is
in progress, so this yak proceeds standalone.

Given the size of a repo-wide flake-parts migration and that `zero` is a
**live, currently-running machine**, this design deliberately scopes to a
zero-only pilot rather than migrating every host.

## Goals

- Prove the flake-parts composition pattern end-to-end on one real machine
  (`zero`) without touching how any other host (`wweaver`, `MegamanX`,
  `darwin-server`, `type-nas`, microvms, etc.) is composed.
- Leave a reusable pattern (`library/machines/<name>.nix`) that Phase 8.6's
  self-updating instance-generation work can build on for future machines.
- Zero functional change to the built system — this is a pure
  refactor of *how* `zero`'s derivation is assembled, not *what* it
  contains.

## Non-goals

- Migrating any other host to flake-parts (explicitly deferred; full
  migration is a separate, much larger yak if pursued later).
- Restructuring `packages`/`apps`/`devShells`/`checks` via flake-parts'
  `perSystem` mechanism — out of scope for this pilot.
- Switching real `zero` hardware to the new configuration. That is an
  explicit human decision after this session's build/eval verification,
  per the yak's own risk note and this repo's rule that agents "should
  only modify Nix configuration files — never directly change computer
  configurations."

## Architecture

Convert `flake.nix`'s `outputs` from a plain lambda to
`flake-parts.lib.mkFlake`. The `flake = { ... }` attribute inside
`mkFlake` contains **everything currently in `outputs`, unchanged**
(`darwinConfigurations`, `nixosConfigurations` for every host except
`zero`, `packages`, `apps`, `devShells`, `checks`, etc.) — a byte-for-byte
passthrough. `zero` is removed from the manual `nixosConfigurations`
block and instead supplied by importing a new flake-parts module,
`library/machines/zero.nix`, via `mkFlake`'s `imports`. That module sets
`flake.nixosConfigurations.zero = libraryLib.mkNixosSystem { ... };` — the
same call that exists today, relocated and using the shared `libraryLib`
module arg (see Cleanup below) instead of a locally re-derived one.

Net effect: every other host is provably unaffected (identical Nix
expressions, just physically inside a different wrapper), while `zero`
becomes the first machine composed through an importable flake-parts
module.

## Components

| File | Change |
|------|--------|
| `flake.nix` | `outputs` becomes `flake-parts.lib.mkFlake { inputs; systems = [...]; imports = [./library/flake-module.nix ./library/machines/zero.nix]; flake = { ...unchanged... }; }`. Remove the `zero` block from the manual `nixosConfigurations` attrset. Extract `mkUser` out of the `outputs` let-block into a new shared file. |
| `library/lib/mk-user.nix` (new) | The `mkUser` helper, moved verbatim from `flake.nix`. `flake.nix` imports it for its own (unchanged) use by other hosts. |
| `library/flake-module.nix` (extended) | Currently only re-exports `modules/` as `flake.nixosModules.library`. Extend it to also provide `_module.args.libraryLib` (from `library/lib/mk-system.nix`) and `_module.args.mkUser` (from `library/lib/mk-user.nix`) as shared module arguments for any flake-parts module that imports alongside it — starting with `library/machines/zero.nix`, and every future per-machine module Phase 8.6 adds. |
| `library/machines/zero.nix` (new) | Flake-parts module: `{ libraryLib, mkUser, ... }: { flake.nixosConfigurations.zero = libraryLib.mkNixosSystem { ...exact same args as today... }; }` |
| `tests/test-phase3-zero.nix` | Extend to keep the existing "zero exists / zero-v2 retired" assertions, and add a structural check that `zero` is now defined via the flake-parts module path (e.g., assert `library/machines/zero.nix` exists and `flake.nix` no longer defines `zero` inline). |
| `modules/common/scripts/nix-cloud-init` | No change — the output name stays `zero`. |

## Auto-update / autoUpgrade impact

None. `autoUpgrade.flakeUrl = "github:funkymonkeymonk/nix#zero"` resolves
to `self.nixosConfigurations.zero` regardless of whether flake-parts or a
plain attrset produced that attribute. The systemd auto-upgrade timer and
manual `nixos-rebuild switch --flake .#zero` are unaffected.

## Testing & verification

- **Eval tests:** Extended `tests/test-phase3-zero.nix` per the Components
  table above — a structural regression guard, not just a behavioral one.
- **Build test:** `nix build .#nixosConfigurations.zero.config.system.build.toplevel --no-link`
  must succeed after the change. This targets `x86_64-linux`; if it can't
  run locally on the primary aarch64-darwin dev machine, it needs to run
  via CI or a Linux builder — confirm availability during implementation
  and flag if it can't be verified before merge.
- **Full suite:** `devenv tasks run check:lint` and `devenv tasks run test:all`.
- **Manual pre-merge verification (human-run, documented in the PR
  description, not automated by the agent):**

  ```bash
  # On the base commit (before this change):
  nix build .#nixosConfigurations.zero.config.system.build.toplevel \
    --no-link --print-out-paths > /tmp/zero-before.txt

  # On this change's commit:
  nix build .#nixosConfigurations.zero.config.system.build.toplevel \
    --no-link --print-out-paths > /tmp/zero-after.txt

  nix store diff-closures $(cat /tmp/zero-before.txt) $(cat /tmp/zero-after.txt)
  # Expect: no diff (identical closure) — proves the flake-parts rewiring
  # is a pure refactor with zero effect on the built system.
  ```

- **Explicitly out of scope:** switching real `zero` hardware. That
  decision and action belong to the human (Will), after reviewing the
  closure diff above.

## Risks

- **Live machine:** `zero` is currently running. This design's build-only
  verification strategy (no SSH to the live host, no `nixos-rebuild
  switch` anywhere in this session) is specifically chosen to keep this
  session's blast radius to Nix eval/build.
- **flake-parts unfamiliarity in this repo:** this is the first real usage
  of the `flake-parts` input, which has been declared but dormant. If
  `mkFlake`'s module-arg propagation behaves unexpectedly (e.g., `inputs`
  not available where assumed, `systems` list mismatch vs the existing
  `forAllSystems` helper), that's a signal to stop and re-scope rather
  than force it — the "hidden complexity upgrades the path" rule applies.

## Acceptance criteria (supersedes/narrows the original yak's criteria)

- [ ] `flake.nix`'s `outputs` uses `flake-parts.lib.mkFlake`
- [ ] Every host except `zero` is defined identically to before, inside
      `flake = { ... }`
- [ ] `zero` is defined in `library/machines/zero.nix`, not inline in
      `flake.nix`
- [ ] `library/flake-module.nix` provides `libraryLib` and `mkUser` as
      shared module args
- [ ] `library/lib/mk-user.nix` exists; `flake.nix` imports it for its own
      use
- [ ] `tests/test-phase3-zero.nix` passes and asserts the new structural
      invariant
- [ ] `nix build .#nixosConfigurations.zero.config.system.build.toplevel --no-link` succeeds
- [ ] `devenv tasks run check:lint` and `devenv tasks run test:all` pass
- [ ] PR description includes the manual closure-diff command block above
      for Will to run before merge
- [ ] No hardware switch performed by the agent
