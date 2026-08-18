---
name: nix-adding-services
description: >
  Use when adding a new service to a Nix flake — creating packages from
  upstream repos (Go, Node, Python), writing service modules, managing
  configs, wiring secrets, and testing. Covers the full lifecycle from
  source to running daemon.
---

# Adding a New Service to a Nix Flake

## Overview

Every new service follows the same lifecycle: source → package → config → secrets → service → test → target → validate. See [references/lifecycle-detail.md](references/lifecycle-detail.md) for the full worked example of each step (packaging patterns for Node/Rust/Go/Python, launchd/systemd modules, opnix secrets, tests, target wiring).

## Full Lifecycle Flow

```
Source URL
   │
   ▼
Package (overlay + flake.nix)
   │
   ▼                   ┌──────────────────┐
Config (options.nix)──► Service Module    │
   │                   │ (darwin.nix for  │
   ▼                   │  macOS, nixos.nix│
Secrets (opnix)        │  for Linux)      │
   │                   └──────────────────┘
   ▼
Home-manager module (if user-level config needed)
   │
   ▼
Tests (tests/test-*.nix + test-coverage.nix)
   │
   ▼
Target config + flake.nix imports
   │
   ▼
Validate: build + switch
```

**Full step-by-step with code for every step**: [references/lifecycle-detail.md](references/lifecycle-detail.md)

## Key Decisions

- **Node/npm source** → `buildNpmPackage`, needs `npmDepsHash` (build once with `lib.fakeHash` to get the real value)
- **Go source** → `buildGoModule`, needs `vendorHash` (same fakeHash trick)
- **Rust source** → `rustPlatform.buildRustPackage`, needs `cargoHash` (same fakeHash trick)
- **Existing Homebrew binary** (skip packaging) → reference `/opt/homebrew/bin/<tool>` directly
- **Already in nixpkgs** → no overlay needed, use `pkgs.<name>` directly
- **Darwin service** → `launchd.daemons` (not `user.agents`) so nix-darwin auto-reloads on switch; always set `UserName`
- **Needs 1Password secrets** → see the `nix-opnix-secrets` skill for the full pattern
- **User-level config file** → home-manager module with `xdg.configFile`, `force = true` if Nix-managed

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Shell script in `writeShellScriptBin` | "Is a directory" at activation | Use `writeShellScript` instead |
| launchd `$HOME` unexpanded | Exit 78 (EX_CONFIG) | Use explicit `/Users/name/...` path |
| User agent won't restart | Old script after switch | Use `launchd.daemons` + `UserName` instead |
| `buildNpmPackage` npmDepsHash | Hash mismatch | Build once with wrong hash, copy error output |
| Google Fonts fetch in sandbox | Build failure | Patch layout.tsx in `preBuild` with sed |
| npm peer deps conflict | `npm install` fails | Add `npmFlags = ["--legacy-peer-deps"]` |
| opnix secret file missing | Activation script fails | Move `entryAfter` to `["installPackages"]` |
