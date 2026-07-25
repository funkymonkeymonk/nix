# Flake Decomposition: Phase 7 Closeout + Phase 8 Kickoff Plan

**Date**: 2026-07-19
**Status**: Draft — ready for review
**Relates to**: [2026-05-11-flake-decomposition-design.md](./2026-05-11-flake-decomposition-design.md)
**Yak**: Flake decomposition > Flake decomposition: Phase 7 — migrate wweaver

---

## Why this plan exists

The original design doc (Section 2–3) called for a three-flake split: `library/`
(building blocks), `schema/` (a `myProfile.*` contract), and `profiles/`
(per-user preference flakes, e.g. `profiles/wweaver/profile.nix`). Phases 0–6
followed that plan literally: parallel `<machine>-v2` outputs built with
`libraryLib.mkDarwinSystem` / `mkNixosSystem`, gated by `nix store
diff-closures`, then old outputs deleted.

**Partway through, the approach pivoted.** PR #337 deleted `profiles/` and
`schema/` as "unused" — nothing in the repo ever consumed `mkProfile` or
imported a profile flake; `mkUser` in `flake.nix` already did the same job with
far less ceremony. PR #348 replaced the schema/profile split with a simpler
two-archetype pattern (`library/archetypes/base-darwin.nix` +
`workstation-darwin.nix`, composed directly in `flake.nix`), and PRs #350–#352
moved `darwin-server`, `MegamanX`, and **wweaver** straight onto that pattern —
**with no `-v2` twin and no closure-diff gate**, because there was no separate
"old" output to diff against; the existing `darwinConfigurations.wweaver`
entry was edited in place.

Net effect: **wweaver is already migrated.** The stale yak context (written
during the original 3-flake plan) references `targets/wweaver/default.nix`,
`profiles/wweaver/profile.nix`, and `library/archetypes/developer-laptop-darwin.nix`
— none of which exist anymore. This plan corrects the tracker and defines what
*actually* remains before touching `flake-parts`.

---

## Verified current state (as of this plan)

| Item | Status |
|---|---|
| `hosts/wweaver/default.nix` | Exists, 132 lines, imports `workstation-darwin.nix` |
| `hosts/megamanx/default.nix` | Exists, same pattern (sibling machine, same archetype) |
| `hosts/darwin-server/default.nix` | Exists, imports `headless-server-darwin.nix` |
| `targets/wweaver/`, `targets/MegamanX/` | **Deleted** (removed in #351/#352) |
| `profiles/`, `schema/` | **Deleted** (removed in #337) |
| `flake-parts` input | Declared in `flake.nix:60`, **never wired into `outputs`** |
| `devenv tasks run check:lint` | ✅ passes |
| `devenv tasks run test` | ✅ passes (eval + build checks, foundation suite) |
| `darwinConfigurations.wweaver` | Single output, uses `base-darwin` + `workstation-darwin` + `hosts/wweaver` |
| `darwinConfigurations.darwin-server` vs `darwin-server-v2` | **Two divergent outputs still coexist** — `darwin-server` already uses new `hosts/darwin-server`; `darwin-server-v2` still points at the old `targets/darwin-server` (leftover from before the pivot, now itself stale) |
| `libraryLib.mkDarwinSystem` / `mkNixosSystem` | Still used by several `-v2` outputs (`darwin-server-v2`, `zero-v2`, `type-server-v2`, `type-server-arm-v2`, `type-desktop-v2`, `core-v2`) — some of these may be dead code now |

---

## Step A — Correct the yak tracker (do first, no code changes)

1. Rewrite Phase 7's context via `yx context "Flake decomposition: Phase 7 — migrate wweaver"`:
   - Replace the stale acceptance criteria (profile.nix, developer-laptop-darwin.nix, wweaver-v2, diff-closures gate) with a note explaining the pivot (link this doc).
   - New acceptance criteria:
     - [ ] `hosts/wweaver/default.nix` confirmed to import `base-darwin.nix` + `workstation-darwin.nix` (already true)
     - [ ] `hosts/wweaver/default.nix` has no leftover references to deleted `profiles/`/`schema/` paths (already true — grep clean)
     - [ ] `devenv tasks run check:lint` and `devenv tasks run test` pass at HEAD (already true, verified above)
     - [ ] Parity check against `hosts/megamanx/default.nix`: same archetype import, same shape of overrides (roles, vane, opencode) — confirmed via diff
2. `yx done "Flake decomposition: Phase 7 — migrate wweaver"`
3. `yx tag rm "Flake decomposition: Phase 8 — cleanup" "@blocked"`
4. `yx sync`

This step is pure bookkeeping — closing a yak whose real-world work already
shipped under different PRs, and un-blocking Phase 8.

---

## Step B — Rewrite Phase 8's context to reflect the pivot

Phase 8's current acceptance criteria still assume the abandoned schema/profile
split ("Remove `mkUser` helper... replaced by profile data"). Since you've
confirmed you **still want flake-parts composition** (Section 6 of the design
doc), Phase 8 becomes: adopt flake-parts for real, on top of the
`hosts/`+`archetypes/` pattern that already won — not resurrect
`schema/`/`profiles/`.

Revised Phase 8 scope, broken into flat sub-yaks (per the skill's dependency
model — flat children + `## Prerequisites`, not deep nesting):

### 8.1 — Audit and resolve duplicate/superseded outputs
**Why first**: you can't safely restructure `flake.nix` while it contains
outputs that silently diverged (e.g. `darwin-server-v2` still importing the
deleted-in-spirit `targets/darwin-server` pattern while `darwin-server` itself
already moved to `hosts/darwin-server`).

- [ ] For each `-v2` output (`core-v2`, `darwin-server-v2`, `bootstrap-v2`,
      `zero-v2`, `type-server-v2`, `type-server-arm-v2`, `type-desktop-v2`,
      `dev-vm-v2`, `openclaw-v2`, `matrix-v2`, `media-center-v2`): determine
      whether it's (a) the machine's *current* real output (no non-`-v2`
      twin exists, or the twin is stale/removable), (b) a genuine
      still-in-progress migration, or (c) dead code safe to delete outright.
- [ ] Document the verdict per output in a table (this doc or a new one).
- [ ] Delete confirmed-dead outputs; rename confirmed-winners to drop `-v2`.

### 8.2 — Decide `targets/` fate per remaining machine
- [ ] `targets/bootstrap` — used by both `bootstrap` and `bootstrap-v2`; resolve per 8.1, then decide keep-as-is (bootstrap is intentionally minimal, may not need archetype treatment) vs migrate.
- [ ] `targets/zero`, `targets/type-nas`, `targets/microvms`, `targets/installer-iso`, `targets/lume-vms`, `targets/hardware-stub.nix`, `targets/type-darwin-server` — audit each against 8.1's verdicts; migrate to `hosts/` + archetype pattern where a clean host file makes sense, or explicitly mark "stays as `targets/`, not in scope" with rationale.
- [ ] Note: `type-nas` was explicitly deferred in the design doc ("write it natively as `library/archetypes/nas.nix`") — check if PR #283 ever landed; if not, this is still open work.

### 8.3 — Wire flake-parts into root `flake.nix`
**Prerequisites**: 8.1 and 8.2 (need a settled, non-divergent output list before restructuring the composition mechanism).

- [ ] Add `imports = [ flake-parts.lib.mkFlake ... ]` per Section 6 of the design doc, but scoped to what actually exists now (`library/flake-module.nix` + wherever `hosts/` composition ends up — schema/profiles imports are dropped since those dirs are gone).
- [ ] Verify `library/flake-module.nix` (currently just re-exports `modules/` as a NixOS module) is sufficient, or needs to grow to also expose archetypes/lib.
- [ ] `devenv tasks run check:all` passes after wiring.
- [ ] CI still validates all remaining configs (no silent output drops).

### 8.4 — Remove now-genuinely-dead helpers
**Prerequisites**: 8.3.

- [ ] Re-evaluate `mkUser` in `flake.nix` — it is **actively used** by `hosts/wweaver`, `hosts/megamanx`, `hosts/darwin-server` today (unlike the original plan's assumption it'd be replaced by profile data). Do NOT remove; instead consider whether it should move into `library/lib/` as part of the flake-parts wiring.
- [ ] Remove `flake-parts` input if 8.3 is abandoned instead (fallback path — see open question below).
- [ ] Remove any `mkMicrovm`/legacy helpers confirmed dead by 8.1.

### 8.5 — Final validation
- [ ] `devenv tasks run check:all` passes
- [ ] CI pipeline green on all remaining configs
- [ ] `hosts/wweaver` (and siblings) unaffected — confirm via `nix build --impure .#darwinConfigurations.wweaver.system` before/after

---

## Resolved: the "why" for flake-parts is instance self-provisioning

The open question above ("is there a new use case driving flake-parts, or is
it just cleaner composition?") is now answered: **yes — self-updating
instance generation.** The near-future goal is to point at this repo and
generate a flake for a *new* machine instance that composes multiple flake
parts (library archetypes + machine-local overrides) and then keeps that
instance up to date automatically, without hand-editing the monolithic root
`flake.nix` per machine.

This reframes 8.3 from "restructure `flake.nix` for its own sake" to
"restructure `flake.nix` so a new instance can be generated and self-maintain
without a PR to this repo touching `outputs`." Concretely, that means the
library needs an externally-callable entry point (`mkDarwinSystem` /
`mkNixosSystem` already exist for this in `library/lib/mk-system.nix`) plus a
scaffolding step (template or generator) that produces a minimal
per-instance flake — this repo's `flake.nix` stops being the *only* place new
machines can be declared.

### Pre-existing building blocks (already real, not hypothetical)

| Piece | Status | Relevance |
|---|---|---|
| `library/lib/mk-system.nix` (`mkDarwinSystem`, `mkNixosSystem`) | Exists, used by several `-v2` outputs | This is the composition function an instance flake would call |
| `modules/nixos/base.nix` `system.autoUpgrade` | Exists, wired via `myConfig.autoUpgrade.flakeUrl` | **NixOS-only.** Already gives self-update today for `zero`, `type-server`, `type-desktop` |
| nix-darwin `system.autoUpgrade` (upstream PR nix-darwin#1682) | **Still open, unmerged** (checked live: `state: open, merged: false`) | Darwin machines (including wweaver) **cannot** self-update natively yet — no code change here fixes this, it's an upstream blocker |
| `modules/common/scripts/nix-cloud-init` + `switch-nix` | Exists, hardcodes `darwin_targets=("MegamanX" "wweaver" "core-v2")` / `nixos_items=(zero, type-server, ...)` | Manual provisioning path today; hardcoded target list is itself evidence this needs to become data-driven if instance generation becomes real |
| `docs/how-to/setup-openclaw-microvm-automated.md`-style cloud-init flow | Exists for microvms | Closest existing analog to "generate + provision + self-maintain an instance" — but for guest VMs, not bare metal/Darwin |

### Constraint this surfaces for Phase 8.3

Any flake-parts design for "generate an instance flake" must account for:
1. **Darwin can't self-upgrade until nix-darwin#1682 merges.** A generated Darwin instance flake can compose cleanly but still requires a human/cron to run `darwin-rebuild switch` — that's not this repo's bug, it's upstream. Track this explicitly rather than silently deferring it.
2. **`nix-cloud-init`'s target lists are hardcoded strings**, not derived from `flake.nix` outputs. If instance generation becomes real, either the tool needs to read available targets from the flake (`nix flake show --json`), or the generated instance flake supplies its own bootstrap and never touches the shared `nix-cloud-init` script's hardcoded list at all.
3. **NixOS instances already have a working self-update story** (`autoUpgrade.flakeUrl`). The flake-parts work for NixOS instance generation is mostly "make composition ergonomic," not "invent self-update from scratch."

### Added sub-yak: 8.6 — Design instance-flake generation

**Prerequisites**: 8.3 (flake-parts wiring must land first — this depends on `library/` being cleanly callable as a sub-flake).

- [ ] Decide the interface: is a generated instance a *standalone flake* with `inputs.library.url = "github:funkymonkeymonk/nix?dir=library"` (per Section 2 of the design doc's original `?dir=` pattern), or a data file consumed by this repo's own `flake.nix` (closer to how `machines/wweaver.nix` was envisioned in Section 7)?
- [ ] Prototype one instance (suggest a disposable NixOS target like `type-server`, which already has working `autoUpgrade` — avoids the Darwin upstream blocker for the first proof-of-concept) generated end-to-end: template → composed flake → boots → self-updates on schedule with no further manual steps.
- [ ] Document the Darwin gap explicitly (link nix-darwin#1682) so "self-updating Darwin instance" isn't silently assumed solved by this work.
- [ ] Decide whether `nix-cloud-init`'s hardcoded target lists get replaced by flake introspection, or become irrelevant because generated instances carry their own bootstrap.

---

## Immediate next actions (in order)

1. Run Step A (yak correction) — I've already claimed the Phase 7 yak; will
   mark it done once you confirm this plan looks right.
2. Run Step B — rewrite Phase 8's yak context with the 8.1–8.6 breakdown above
   as flat sub-yaks under it (per the skill's flat-hierarchy + `## Prerequisites`
   convention), tagging 8.2–8.6 `@blocked` on their stated prerequisites.
3. Land 8.1 (the audit) as its own PR before any `flake.nix` restructuring —
   it's read-only/documentation until the delete/rename step, low risk, and
   unblocks everything else with confidence.
4. When you're ready to start on 8.6 specifically, revisit this plan — the
   interface decision (standalone flake vs. data file) should probably get
   its own short design note once 8.3 has landed and the shape of
   `library/flake-module.nix` is settled.
