---
title: "Author Nix Tests"
type: how-to-guide
audience: developer
last-reviewed: 2026-06-28
---

# Author Nix Tests

This guide walks through each of the four test patterns used in this repository, with concrete examples from `tests/`.

## Overview

Tests live in `tests/default.nix`, which returns an attrset of Nix derivations. Each key is a check that's wired into the flake's `.checks` output[^1]. Run locally with:

```bash
devenv tasks run test                    # all platform-appropriate checks
nix build .#checks.aarch64-darwin.<name> --no-link  # single check
```

## Pattern 1 — Module Evaluation Tests (Fastest)

**Use when:** You need to verify option defaults, types, guards, or module composition without building anything.

### How it works

`lib.evalModules` evaluates your modules in isolation. Provide minimal stub options that the module references, then assert on the resulting `.config`.

```nix
# tests/test-services.nix (adapted)
{pkgs, ...}: let
  inherit (pkgs) lib;

  # Minimal option stubs — only what the module under test needs
  evalModule = extraConfig:
    (lib.evalModules {
      modules = [
        ../modules/common/options.nix   # real definitions
        {
          options.something.theModuleNeeds = lib.mkOption { /* ... */ };
        }
        {
          config.myConfig = extraConfig;  # test case
        }
      ];
    }).config;

  defaults  = evalModule {};
  customVal = evalModule { foo.enable = true; };
in {
  optionsTest = pkgs.runCommand "test-options" {} ''
    if "${defaults.foo.port}" != "3000"; then
      echo "port default mismatch"; exit 1
    fi
    if "[${customVal.foo.customSetting}]" != "[42]"; then
      echo "custom setting mismatch"; exit 1
    fi
    touch $out
  '';
}
```

Assert at eval-time when possible — failures surface during flake evaluation:

```nix
# tests/test-microvm.nix (adapted)
assertEq = name: expected: actual:
  if actual == expected
  then "${name}: OK"
  else throw "${name}: expected ${toString expected}, got ${toString actual}";
```

### When to use

- Verify option defaults and types
- Test module composition without conflicts
- Platform guards (Darwin vs. NixOS behavior)
- Option cascades between roles

## Pattern 2 — Package Instantiation Tests

**Use when:** A module evaluates fine but you need to confirm referenced packages actually build at this nixpkgs revision and target platform.

### How it works

List packages as `nativeBuildInputs` inside `pkgs.runCommand`. Nix must instantiate them before running the build script, so a missing or broken package fails the derivation[^4].

```nix
# tests/test-packages.nix (adapted)
corePackagesTest = pkgs.runCommand "test-core-packages" {
  nativeBuildInputs = with pkgs; [git curl wget coreutils vim];
} ''
  for cmd in git curl wget vim; do
    command -v "$cmd" > /dev/null || { echo "FAIL: $cmd not on PATH"; exit 1; }
  done
  touch $out
'';
```

### When to use

- Verify foundation packages are available on every platform
- Test custom overlays produce buildable packages
- Confirm service binaries exist before integration tests

## Pattern 3 — Eval-Modules With Real Role Composition

**Use when:** You want to test complex role interactions, option cascades, or multi-module compositions that would be expensive in a VM.

### How it works

Like Pattern 1 but with more real modules imported and realistic test data:

```nix
# tests/test-roles.nix (adapted)
evalWithRole = roleName:
  (lib.evalModules {
    modules = stubModules ++ [
      {
        config.myConfig.users = [...];  # test fixture
        config.myConfig.roles.${roleName}.enable = true;
      }
    ];
  }).config;
```

Then assert that `evalWithRole "developer"` produces the expected `environment.systemPackages` and role cascades. The `allRoleTests` derivation runs dozens of checks in a single build sandbox.

### When to use

- Role → package mapping verification
- Multi-role composition (do roles conflict?)
- Option cascade chains
- Dead-code detection (e.g., verifying removed options are gone)

## Pattern 4 — VM Integration Tests (Slowest)

**Use when:** You must verify runtime behavior — services binding ports, files on disk, boot sequence.

### How it works

Uses `pkgs.testers.nixosTest` to spin up QEMU VMs with Python test scripts[^5]. Only runs on x86_64-linux:

```nix
# tests/vm/default.nix (adapted)
pkgs.testers.nixosTest {
  name = "vm-test-ssh";
  nodes.machine = {...}: {
    imports = [ /* real modules */ ];
    myConfig = { /* test fixtures */ };
    system.stateVersion = "25.05";
    virtualisation.memorySize = 1024;
  };
  testScript = ''
    machine.wait_for_unit("sshd.service")
    machine.wait_for_open_port(22)
  '';
}
```

### When to use

- Service availability (ports, units)
- User/group membership after boot
- Filesystem layout and package installation
- End-to-end workflow testing (e.g., boot → login → service healthy)

## Wiring Tests Into the Flake

Every test file returns an attrset of derivations. Wire them through `tests/default.nix`:

```nix
# tests/default.nix — add new test imports here
{pkgs, ...}: let
  testNewFeature = import ./test-new-feature.nix {inherit pkgs;};
in {
  new-feature-basic = testNewFeature.basicTest;
  new-feature-custom = testNewFeature.customOptionsTest;
}
```

The flake's `checks` output wraps this combinator and returns derivations per-system. CI runs `devenv tasks run test` which invokes `nix flake check --keep-going`[^1].

## Module Coverage Tracking

`tests/test-coverage.nix` auto-discovers `.nix` files under `modules/` using `builtins.readDir`. Add tested module paths to the `testedModules` list. This runs as a regular check — it generates a JSON coverage report and prints untested modules.

To track a new test:

```nix
# In test-coverage.nix, add to testedModules:
"My New Module" = { /* ... */ };
```

### Anti-Pattern Checklist

When writing tests, verify your check passes these rules from the [testing explanation](../explanation/testing.md):

- [ ] Stub minimally — no more options than needed for the module under test
- [ ] Assert at eval-time when possible (Nix `throw`), not only in shell
- [ ] One test file per feature area, not one giant file
- [ ] Tests fail before implementation (RED → GREEN)
- [ ] Update coverage tracking alongside new tests

## References

[^1]: Nix flake check: <https://nix.dev/manual/nix/2.22/command-ref/new-cli/nix3-flake-check>
[^4]: nixpkgs `pkgs.runCommand` semantics — packages in `nativeBuildInputs` must be built before the script runs
[^5]: NixOS Testing Framework: <https://nixos.wiki/wiki/Testing>
