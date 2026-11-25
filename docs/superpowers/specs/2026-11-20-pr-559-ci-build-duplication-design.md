# PR 559 CI Build Duplication Design

## Intent

Prevent PR validation from independently building the same expensive Devenv derivation in the foundation package test and the machine SecretSpec safety test. The canceled PR run shows both shards compiling identical `rust_devenv-*` derivations from a cold cache.

## Approaches

- **Remove the redundant foundation-package build (selected):** Keep the foundation test for the other packages, but do not put `pkgs.devenv` in its `nativeBuildInputs` or command spot-check. `test-devenv-packages.nix` continues to assert that Devenv is included, and the machine SecretSpec safety check continues to execute the pinned Devenv binary. This removes one duplicate full build while retaining actual Devenv CLI coverage.
- **Raise the CI timeout:** Allows the duplicated builds to continue longer but does not reduce duplicated work; not selected because the request was to reduce builds.

## Scope and constraints

Only adjust the package-availability test. Preserve build/runtime coverage through the existing machine SecretSpec test and preserve package-list inclusion coverage through the existing Devenv package metadata test. Do not change CI timeouts or PR 559's flake input/lockfile changes.

## Success criteria

The foundation package check no longer pulls in the Devenv derivation; existing Devenv inclusion and SecretSpec runtime checks remain intact; relevant Nix checks pass.
