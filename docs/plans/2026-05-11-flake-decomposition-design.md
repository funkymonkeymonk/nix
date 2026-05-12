# Flake Decomposition System Design

**Date**: 2026-05-11  
**Status**: In Progress — sections 1–9 decided, profile development and migration pending  
**Participants**: Will Weaver

---

## Overview

This document captures the system design for decomposing the current monolithic
`funkymonkeymonk/nix` flake into a composable, multi-flake architecture. The goal
is a system where:

- The library is a reusable, shareable building block with no personal data
- User preferences are fully portable and separable from any machine
- Machine configs are minimal, private, and derivable at provision time
- Agents can propose changes but cannot self-modify running systems
- All machines self-apply updates via pull-based GitOps

---

## Section 1: The Three-Flake Model

Three distinct concerns, three distinct flakes:

```
Library Flake                    User Profile Flake
github:funkymonkeymonk/nix       github:wweaver/nix-profile
─────────────────────────        ──────────────────────────
Roles, modules, archetypes       Roles enabled
mkUser, mkMicrovm helpers        AI provider config
Machine-type bundles             Email, fullName, username
Pinned nixpkgs/HM versions       Skills preferences
options.nix (myConfig.*)         Work endpoints
Schema exports (profile type)    (no library dependency)

                 ↓ both imported by
          System Flake / cloud-init
          ───────────────────────────
          Platform + hostname
          Which archetype
          Machine-local overrides
          Pulls latest library on build
```

**Key constraint**: Library and profile flakes have no knowledge of each other.
The system flake is the only place they meet.

---

## Section 2: Monorepo Structure

The library flake is a `flake-parts` monorepo exposing three sub-flake types:

```
github:funkymonkeymonk/nix
├── flake.nix                    # root composer (flake-parts)
├── schema/                      # sub-flake: shared profile contract
│   ├── flake.nix                # standalone: ?dir=schema
│   ├── flake-module.nix         # imported by root
│   └── modules/
│       ├── profile.nix          # NixOS module type: myProfile.*
│       └── validator.nix        # mkProfile helper + type checks
├── library/                     # sub-flake: building blocks
│   ├── flake.nix                # standalone: ?dir=library
│   ├── flake-module.nix
│   ├── modules/                 # (current modules/ moves here)
│   ├── archetypes/              # machine-type bundles
│   │   ├── developer-laptop-darwin.nix
│   │   ├── headless-server-darwin.nix
│   │   ├── headless-server-nixos.nix
│   │   ├── desktop-nixos.nix
│   │   ├── microvm-guest.nix
│   │   └── nas.nix              # deferred — added after Phase 0
│   └── lib/                     # mkDarwinSystem, mkNixosSystem, helpers
├── profiles/                    # optional: hosted profiles
│   └── wweaver/
│       ├── flake.nix            # standalone, no library dep
│       └── profile.nix          # exports myProfile attrset
└── systems/                     # (not file-based — derived at provision time)
```

External consumers reference sub-flakes via `?dir=`:
```nix
inputs.library.url = "github:funkymonkeymonk/nix?dir=library";
inputs.schema.url  = "github:funkymonkeymonk/nix?dir=schema";
```

---

## Section 3: The Schema Contract

The schema is the shared language between library and profile. It lives in
`schema/` and is independently importable. The library implements it; the profile
conforms to it; validation happens at system build time.

```nix
# schema/modules/profile.nix
{ lib, ... }: {
  options.myProfile = {
    user = {
      name     = lib.mkOption { type = lib.types.str; };
      email    = lib.mkOption { type = lib.types.str; };
      fullName = lib.mkOption { type = lib.types.str; };
    };
    roles     = lib.mkOption { type = lib.types.attrsOf roleSubmodule; default = {}; };
    opencode  = lib.mkOption { type = lib.types.submodule opencodeOpts; default = {}; };
    providers = lib.mkOption { type = lib.types.attrsOf providerSubmodule; default = {}; };
    skills    = lib.mkOption { type = lib.types.submodule skillsOpts; default = {}; };
    llmEndpoints = lib.mkOption { type = lib.types.attrsOf endpointSubmodule; default = {}; };
  };
}
```

A profile flake exports a single validated attrset using `mkProfile`:

```nix
# profiles/wweaver/profile.nix
{ mkProfile, ... }:
mkProfile {
  user     = { name = "wweaver"; email = "wweaver@justworks.com"; fullName = "Will Weaver"; };
  roles    = { developer.enable = true; opencode.enable = true; };
  opencode = { model = "just-llms/claude-sonnet-4-6"; };
  providers.just-llms = { baseURL = "https://litellm.justworksai.net"; dynamicModels = true; };
}
```

**Profile flake has no library import.** `mkProfile` validates the attrset against
the schema using `lib.evalModules` — errors surface at system build time.

The schema boundary is intentionally fat for now (when in doubt, put it in schema).
Moving options between schema and library is cheap within the monorepo.

---

## Section 4: Composition — `mkDarwinSystem` and `mkNixosSystem`

The library exports two system builder functions. They accept a profile attrset,
an archetype, and machine-local overrides.

```nix
# library/lib/mk-system.nix
mkDarwinSystem = { archetype, profile, hostname, overrides ? {} }:
  inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    specialArgs = { inherit inputs profile; };
    modules = [
      ../modules
      ../archetypes/${archetype}.nix
      { myConfig = lib.mkMerge [ profile (applyOverrides overrides) ]; }
      inputs.self + "/os/darwin.nix"
    ];
  };
```

**Override priority** (highest to lowest):

| Priority | Source |
|----------|--------|
| 50 | Machine overrides (`lib.mkOverride 50`) |
| 100 | Profile values |
| 1000 | Role/archetype defaults |

Machine overrides always win. This is intentional and explicit.

**Profile is fetched at evaluation time** via `builtins.getFlake` — the profile
URL is a string in the machine config, not a locked flake input. This means
profile changes are always live without an inventory lock update.

---

## Section 5: GitOps — Auto-Upgrade

**NixOS machines**: `system.autoUpgrade` is built-in and enabled when
`myConfig.autoUpgrade.flakeUrl` is set. Implemented in `modules/nixos/base.nix`.
Runs at 02:00 with a 45-minute random delay.

**MicroVMs**: Explicitly disabled (`autoUpgrade.flakeUrl = lib.mkForce ""`).
MicroVMs are immutable cattle — they are replaced rather than upgraded.

**Darwin machines**: `system.autoUpgrade` is not yet available in nix-darwin
(PR #1682 open, Jan 2026). A yak tracks contributing to that PR.

**Current machines with auto-upgrade enabled**:

| Machine | Flake URL |
|---------|-----------|
| `type-server` | `github:funkymonkeymonk/nix#type-server` |
| `type-desktop` | `github:funkymonkeymonk/nix#type-desktop` |
| `zero` | `github:funkymonkeymonk/nix#zero` |

---

## Section 6: `flake-parts` Wiring

Root `flake.nix` composes the three sub-flake modules:

```nix
outputs = inputs @ { flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [
      ./schema/flake-module.nix
      ./library/flake-module.nix
      ./profiles/flake-module.nix
    ];
    systems = [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ];
  };
```

Each sub-directory has two entry points:
- `flake-module.nix` — imported by the root, no inputs block
- `flake.nix` — standalone entrypoint for `?dir=` consumers, wraps the module

This pattern lets the monorepo work as a unified flake at the root while each
component remains independently referenceable.

---

## Section 7: Private Inventory Repo

Machine configs live in a **private** repo (`wweaver/nix-inventory`). This repo
is the only place that knows about specific machines.

```
wweaver/nix-inventory (private)
├── machines/
│   ├── wweaver.nix       # Darwin laptop — evaluation-time config only
│   ├── zero.nix          # NixOS desktop
│   ├── type-server-01.nix
│   └── openclaw.nix      # Agent microvm
├── schema.nix            # Validates machine configs at eval time
├── flake.nix             # Composes library + machine configs
└── .github/workflows/
    └── rebuild.yml       # Triggers on merge to main
```

**Machine config** — minimal, only genuinely machine-local values:

```nix
# machines/wweaver.nix
{
  platform  = "aarch64-darwin";
  archetype = "developer-laptop-darwin";
  profile   = "github:wweaver/nix-profile";
  hostname  = "wweaver";

  overrides = {
    vane.colima = { cpu = 6; memory = 12; disk = 60; };
    ollama.host = "0.0.0.0";
  };
}
```

**Secret split**:

| Evaluation-time (inventory, not secret) | Activation-time (1Password via opnix) |
|-----------------------------------------|---------------------------------------|
| archetype, platform, hostname | API keys, passwords |
| roles enabled | SSH keys, service tokens |
| profile flake ref | Signing certificates |
| overrides (hardware sizing, topology) | 1Password service account token |

**1Password bootstrap**: A 1Password service account token is the one secret
injected at provision time (via cloud-init or equivalent). It bootstraps opnix
which then pulls all other secrets.

**Agent PR flow**:

1. Agent writes proposed change to `machines/<name>.nix`
2. Opens PR with fine-grained PAT (PR creation only, no merge permission)
3. PR body includes: `agentId`, `purpose`, `justification`, config diff
4. Branch protection requires human approval
5. Merge triggers `rebuild.yml` GitHub Action
6. Action SSHes to affected machine and runs appropriate rebuild
7. New generation activates; opnix pulls secrets from 1Password

**Agent identity** is baked into both the machine config (`agentId`, `agentPurpose`)
and the PAT used to open the PR. GitHub audit logs show the PAT name as the actor.

---

## Section 8: Library Developer Workflow

### Feedback Loop

Four stages, each gating the next:

```
check:lint         ~1s      syntax, formatting (alejandra), dead code (deadnix)
test:nixos-eval    ~90s     module errors, option conflicts, type mismatches
test:darwin-eval   ~90s     Darwin-specific option availability
build:nixos        ~5-15m   full derivation via Determinate nix-builder (macOS native)
build:darwin       ~5-15m   full Darwin derivation
```

`build:nixos` on Darwin uses Determinate Nix's native Linux builder (Virtualization
framework via `determinate-nixd`). No remote builder or Docker required. Fully
equivalent to CI Linux output.

CI runs each build on its native platform — no matrix changes needed.

### Input Override System

Override the library or profile input at build/test time via environment variables:

| Variable | Effect |
|----------|--------|
| `NIX_LIBRARY_BRANCH` | Use this branch of the library repo |
| `NIX_LIBRARY_REPO` | Use this repo (different fork) |
| `NIX_LIBRARY_PATH` | Use local path (highest priority) |
| `NIX_PROFILE_BRANCH` | Use this branch of the profile repo |
| `NIX_PROFILE_REPO` | Use this profile repo |
| `NIX_PROFILE_PATH` | Use local profile path |

Priority: `PATH` > `REPO`+`BRANCH` > `flake.lock` pin

**Auto-set via direnv** — `.envrc` reads the current jj bookmark and sets
`NIX_LIBRARY_BRANCH` automatically:

```bash
# .envrc
_current_branch=$(jj log -r @ --no-graph -T 'bookmarks' 2>/dev/null | tr -d ' ')
if [[ -n "$_current_branch" && "$_current_branch" != "main" ]]; then
  export NIX_LIBRARY_BRANCH="$_current_branch"
fi
```

Rule: **on `main` → unset (use flake.lock pin). On any feature/fix/chore branch →
set automatically.** No release branches in this repo.

### Typical Library Workflow

```bash
# 1. Start isolated workspace (stored in ~/.jj/workspaces/, never sibling dirs)
/workspace feat/new-role          # via OpenCode, or:
jj-workspace create feat/new-role

# 2. Fast feedback during development
devenv tasks run check:lint
devenv tasks run test:nixos-eval

# 3. Full build before pushing (NIX_LIBRARY_BRANCH auto-set by direnv)
devenv tasks run build:nixos

# 4. Push and create PR
jj-pr feat new-role "Add llm-gateway role"

# 5. Clean up workspace
jj-workspace remove feat/new-role-<date>-<id>
```

### Branch Strategy

```
main          ← stable, machines track this, protected
feat/*        ← features, PR required
fix/*         ← bug fixes, PR required
chore/*       ← lock updates, dependency bumps
```

Lock-only updates (`nix flake update`) can push directly to `main` — no PR needed.

### jj Workspace Convention

Workspaces are stored in a **fixed location** (`~/.jj/workspaces/<repo>/`), never
as sibling directories to the repo. They are conceptually branches you `cd` into.

- Humans: optional for small changes, recommended for multi-session work
- Agents: always use workspaces (isolation requirement)
- Agent naming: `feat/agent-<agentId>-<topic>`

See yak "Standardize jj workspace workflow for humans and agents" for full
implementation plan.

---

## Section 10: Profile Development Workflow

The profile flake is deliberately simple — a validated attrset with one dependency
(the schema). No modules, no imports, no build system.

### Structure

```
github:wweaver/nix-profile (private)
├── flake.nix        # exposes myProfile, imports schema only
├── profile.nix      # the actual preferences
└── flake.lock       # pins schema version only
```

```nix
# flake.nix
{
  inputs.schema.url = "github:funkymonkeymonk/nix?dir=schema";
  outputs = { schema, ... }: {
    myProfile = schema.lib.mkProfile (import ./profile.nix);
  };
}
```

### Feedback Loop

```
nix eval .#myProfile    ~2s    validates against schema, catches type errors
```

Profile produces no derivations — it's pure data. No build step needed.
Full system validation happens from the inventory side using `NIX_PROFILE_BRANCH`.

### Typical Workflow

```bash
# Edit profile.nix
nix eval .#myProfile          # validate

# Push directly to main — no PR gate for personal preferences
jj describe -m "feat: add new LLM provider"
jj git push
# Profile is live — next machine rebuild picks it up automatically
```

### Testing Against a Specific Library Version

```bash
# From inventory repo — compose any combination of overrides
NIX_PROFILE_BRANCH=feat/new-provider \
NIX_LIBRARY_BRANCH=feat/new-role \
devenv tasks run build:darwin
```

### Schema Versioning

The schema uses semver with **heavy bias toward additive-only changes**:

| Change type | Version bump | Profile impact |
|-------------|-------------|----------------|
| New field + default | Minor (1.0→1.1) | Zero — existing profiles unaffected |
| New required field | **Blocked by CI** | Must add default first |
| Rename/remove field | Major (1.x→2.0) | Ceremony required |

Profile declares schema compatibility:
```nix
{ _schemaVersion = "1.x"; ... }   # accepts any 1.x
```

**Most options must have defaults.** Only `user.name`, `user.email`, and
`user.fullName` are legitimately required. Everything else defaults to empty/disabled.
This is enforced by schema lint in library CI.

### Breakage Detection (Three Layers)

| Layer | What it catches | When |
|-------|----------------|------|
| Library CI | Hosted profiles (`profiles/*`) break on schema change | Before PR merges |
| Profile repo CI | External profile breaks on schema lock update | On next `nix flake update schema` |
| Schema lint | New required field without default | Before PR merges |

External profiles import a reusable conformance test from the schema:
```nix
# .github/workflows/validate.yml
- run: nix eval .#myProfile   # schema pin controls which version validates
```

Major version bumps require: deprecated v1 output kept during migration window,
auto-opened migration PRs for hosted profiles, clear error message with migration
guide link for external profiles.

---

## Section 11: Migration Path

**Principle**: Never break a running machine. Run old and new outputs in parallel;
delete old only after each machine is confirmed working on the new path.

### Machine Inventory and Migration Order

Migration order is **last-to-first** by risk. Protect daily drivers until last.

```
Phase 1  MicroVMs (dispensable — replaced not upgraded)
         dev-vm, openclaw, matrix, media-center

Phase 2  Cattle NixOS (templates — no specific machine running them)
         type-server, type-server-arm, type-desktop

Phase 3  zero (NixOS desktop — real machine but recoverable)

Phase 4  darwin-server (headless Darwin — SSH recoverable)

Phase 5  core + bootstrap (minimal configs — low risk)

Phase 6  MegamanX (Darwin daily driver — second to last)

Phase 7  wweaver (primary machine — absolute last)
```

### Archetype Naming Convention

Archetypes use role-based names. Platform suffix is added only when the archetype
is inherently platform-specific and a cross-platform equivalent could exist:

- **Platform-agnostic**: just the role — `nas`, `microvm-guest`
- **Platform-specific**: role + platform — `developer-laptop-darwin`, `headless-server-nixos`

`type-server-arm` collapses into `headless-server-nixos` — the `system` parameter
to `mkNixosSystem` handles the architecture difference.

| Current name | New archetype name |
|---|---|
| `type-server` | `headless-server-nixos` |
| `type-server-arm` | `headless-server-nixos` (system param handles arch) |
| `type-desktop` | `desktop-nixos` |
| `darwin-server` target | `headless-server-darwin` |
| microvms | `microvm-guest` |
| wweaver, MegamanX targets | `developer-laptop-darwin` |
| type-nas (deferred) | `nas` |

---

### Open PR Decisions

**PR #284 (deploy-rs + protoman)**: Merge as-is. Protoman is a `darwin-server`
instance — same archetype as `darwin-server`. Deploy-rs is a temporary workaround
because nix-darwin `system.autoUpgrade` doesn't exist yet (PR #1682). When #1682
lands, protoman moves to pull-based auto-upgrade and deploy-rs is removed.

**PR #283 (type-nas)**: Defer until after Phase 0. Since type-nas is new
infrastructure that doesn't exist anywhere yet, write it natively as
`library/archetypes/nas.nix` from the start rather than migrating it later.
PR stays open, rebases onto Phase 0 output.

---

1. Add `flake-parts` input
2. Create `schema/` with profile type + `mkProfile`
3. Create `library/flake-module.nix` wrapping existing `modules/`
4. Create `library/archetypes/` from current `machine-types/`
5. Create `library/lib/mk-system.nix` with builder functions
6. Create `profiles/wweaver/` with profile attrset
7. All existing configurations remain **unchanged**

Validation: `devenv tasks run check:all` passes. No machines touched.

### Phase 1–7: Per-Machine Pattern

Each machine follows the same four-step pattern:

```
1. Add <machine>-v2 output using new library (parallel to old)
2. Build and diff closures:
   nix store diff-closures .#<machine> .#<machine>-v2
3. If diff is clean: switch machine to v2
4. Monitor, then delete old output
```

**Closure diff is the critical gate** — empty diff (or only expected changes)
means the migration is safe. Any unexpected additions/removals warrant investigation.

### Rollback at Every Phase

Old outputs remain until explicitly deleted. If anything breaks after switching:

```bash
sudo nixos-rebuild switch --rollback          # NixOS
darwin-rebuild switch --flake .#<machine>-old # Darwin
```

### Phase 8: Cleanup

Once all machines on new path:
- Remove `targets/` directory
- Remove `machine-types/` directory
- Simplify `flake.nix` to pure `flake-parts` composition

### Stacked PRs

Each phase is a separate PR stacked on the previous. Validate, merge, continue:

```
PR: Phase 0 — Foundation (schema, library structure, flake-parts)
 └── PR: Phase 1 — MicroVM migration
      └── PR: Phase 2 — Cattle NixOS migration
           └── PR: Phase 3 — zero migration
                └── PR: Phase 4 — darwin-server migration
                     └── PR: Phase 5 — core + bootstrap migration
                          └── PR: Phase 6 — MegamanX migration
                               └── PR: Phase 7 — wweaver migration
                                    └── PR: Phase 8 — cleanup
```

Each PR is independently reviewable and mergeable. Blocking a phase blocks all
downstream phases naturally via GitHub's stacked PR base branch dependencies.

---

## Key Decisions Log

| Decision | Rationale |
|----------|-----------|
| Library and profile have no mutual dependency | Clean composition, profile stays portable |
| Schema lives in library monorepo (Option B) | Enables independent validation without circular deps |
| Profile validation at system build time | Profile flake needs no library import |
| Overrides always win (priority 50) | Unambiguous, predictable, no surprise profile values on a machine |
| Profile fetched live via `builtins.getFlake` | Profile changes are always current without lock updates |
| Evaluation-time config in private inventory repo | Not sensitive, human-readable, agent-PRable |
| Activation-time secrets in 1Password via opnix | Already in use, access-controlled, auditable |
| 1Password service account token as bootstrap secret | One secret in, everything else pulled |
| MicroVMs never auto-upgrade | Immutable cattle — replaced not patched |
| Determinate nix-builder for local Linux builds | Full build parity on Darwin, no remote builder |
| `NIX_LIBRARY_BRANCH` auto-set by direnv | Builds naturally target current branch, no manual flags |
| No release branches | Repo uses main + feature branches only |
| Schema semver with additive bias | Breaking changes exist as escape hatch, not routine tool |
| Most schema options must have defaults | Only user.name/email/fullName are legitimately required |
| Three-layer breakage detection | Library CI (hosted), profile CI (external), schema lint (new options) |
| Migration order: MicroVMs first, wweaver last | Protect daily drivers until proven safe |
| Parallel outputs during migration | Old output exists until machine confirmed on new path |
| `nix store diff-closures` as migration gate | Empty diff = safe to switch |
| Stacked PRs per migration phase | Validate and merge each phase independently |
