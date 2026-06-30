---
title: "Testing Pyramid"
type: explanation
audience: developer
last-reviewed: 2026-06-28
---

# Testing Pyramid

This repository uses a layered testing strategy modeled on the Nix community's recommended practices[^1][^2]. Tests are organized by what they validate and the cost to run — from cheap evaluation-time checks to full VM-based integration tests.

## Overall Structure

```
                  ┌───────────────┐
                  │  VM Tests     │  ← Full NixOS VM, boots real systems
                  │  (slowest)    │
                  ├───────────────┤
         ┌────────│ Eval Deriv.   │
         │        │ Packages      │  ← pkgs.runCommand with build inputs
         ├────────┼───────────────┤
         │        │ Eval Modules  │  ← lib.evalModules with stubs
   Fast ─┤        │ (cheap test)  │  ← Runs at nix-evaluation time
         ├────────┼───────────────┤
         │        │ Module Tests  │  ← Pure Nix, no build sandbox needed
         └────────│───────────────┘
                  (fastest)
```

Every layer runs via `flake.checks` and is invoked by `devenv tasks run test` in CI[^1].

## Why This Pyramid?

### Tests at evaluation time catch the most errors

Nix modules express declarative configuration. Most bugs in module code are *evaluation* errors — wrong option types, missing guards, invalid compositions. These surface immediately if you eval modules before ever building a derivation[^3]. `lib.evalModules` with minimal stubs is the cheapest and fastest first line of defense.

### Build-time tests verify packages actually exist

Even if a module evaluates cleanly, a referenced package might fail to build at your pinned nixpkgs revision or be missing from your target platform. Wrapping assertions in `pkgs.runCommand` with real packages as `nativeBuildInputs` forces the evaluation and instantiation of those packages[^4]. This catches "evaluates fine but doesn't install" bugs that pure eval misses.

### VM tests verify runtime behavior

Nothing substitutes for booting a real system. The NixOS testing framework provides QEMU-based VMs with a Python test API for waiting on services, checking ports, and running commands[^5]. These tests are the most expensive but catch integration issues — service conflicts, dependency ordering, and actual filesystem layout.

## What Each Layer Tests

| Layer | Tests | Cost | Where |
|-------|--------|------|-------|
| Module tests (eval) | Option defaults, option types, custom values, guards, role cascades | Fastest — pure Nix eval | `tests/test-*.nix` using `lib.evalModules` |
| Package tests (build) | Packages are instantiable, services start, config files exist | Medium — build sandbox, no VM | `tests/test-*.nix` using `pkgs.runCommand` |
| VM tests (integration) | Services bind ports, files on disk, boot sequence | Slowest — QEMU VM | `tests/vm/` using `pkgs.testers.nixosTest` |
| Coverage tracking | Which modules are tested by what | Free — eval-time analysis | `tests/test-coverage.nix` |

## Key Principles

### 1. Stub minimally, test maximally

Tests use minimal stub modules that provide just enough option definitions for the module under test to evaluate[^3]. This is a form of dependency injection — you control what's available and can simulate Darwin vs. NixOS by stubbing `options.boot`. The pattern used through this repo:

```nix
let
  eval = pkgs.lib.evalModules {
    modules = [
      ../modules/common/options.nix   # Real option definitions
      {
        options.myConfig.foo.enable = pkgs.lib.mkOption { /* ... */ };
      }                                # Minimal stubs for referenced attrs
    ] ++ [{ config.myConfig.foo.enable = true; }];
  };
in eval.config
```

This matches the upstream nix-unit philosophy of "tests live where the module lives" and keep their test context minimal[^2].

### 2. Assertions in Nix, not just shell

Shell assertions (`echo` + `exit 1`) work fine for build-time checks, but when possible, perform assertions at **evaluation time** inside Nix itself. This means failures are caught during flake evaluation, before any build happens — the fastest feedback possible[^2]. The repo uses a `builtins.throw` pattern for eval-time assertions.

### 3. Platform-aware testing

Darwin and NixOS have different option sets. Tests that need to verify platform-specific behavior either:
- Run on the matching platform only (guarded by `pkgs.stdenv.hostPlatform`)
- Stub the missing platform's key options (`options.boot` for NixOS detection)

The coverage tracker in `tests/test-coverage.nix` auto-discovers modules so coverage stays accurate as the codebase grows.

### 4. One test file per feature area

Each test file corresponds to a module or role group:
- `test-roles.nix` — all roles and their cascades
- `test-services.nix` — vane, ollama, openclaw modules
- `test-sketchybar.nix` — sketchybar configuration testing

This matches the nix-unit recommendation that tests live near the logic they're testing[^2], adapted for a flat `tests/` tree.

### 5. Tests should fail before you implement

Following TDD principles, write the test *before* implementing the module or making changes. The test must first fail (RED), then pass after implementation (GREEN)[^3]. This ensures tests actually exercise new code rather than being green by accident.

## CI Wiring

All checks are wired into `flake.checks` via the `tests/default.nix` combinator, which returns an attrset of derivations. Both macOS and Linux CI runners execute `devenv tasks run test`, which runs the platform-appropriate subset[^1]. VM tests are gated on `isLinux` because the NixOS testing framework requires QEMU[^5].

## Anti-Patterns to Avoid

| Anti-Pattern | Why It's Bad | Fix |
|-------------|-------------|-----|
| No stubs at all | Tests require full system boot — slow and brittle | Use `lib.evalModules` with minimal stubs |
| All tests in one file | Hard to find which test failed; long CI runs | One file per feature area |
| Manual module coverage updates | Coverage drifts as modules are added/removed | Auto-discover with `builtins.readDir` |
| Testing implementation details | Tests break when internal structure changes | Test outcomes, not mechanisms (BDD style) |

## Further Reading

- [Reference: Test Patterns](../reference/test-patterns.md) — Concrete examples of each pattern
- nix-unit documentation[^2]
- Nix flake check reference[^1]
- NixOS Testing Framework[^5]

---

[^1]: Nix Reference Manual, "nix flake check": <https://nix.dev/manual/nix/2.22/command-ref/new-cli/nix3-flake-check>
[^2]: nix-unit — Nix community testing framework: <https://github.com/nix-community/nix-unit>, <https://clan.lol/blog/nix-unit/>
[^3]: Blake Smith, "Running NixOS Tests with Nix Flakes": <http://blakesmith.me/2024/03/02/running-nixos-tests-with-flakes.html>
[^4]: nixpkgs manual on `pkgs.runCommand`: packages instantiated via `nativeBuildInputs` are evaluated and built before the build script runs. See `man 1 deriver` for derivation semantics.
[^5]: NixOS Wiki, "Testing": <https://nixos.wiki/wiki/Testing>
