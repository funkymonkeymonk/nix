# Machines Build Remote Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make named `machines:build` operations route non-local `aarch64-darwin` builds through the MegamanX remote builder.

**Architecture:** Extend the existing `scripts/machine-ops.sh build` path. Same-system builds remain local; cross-system builds use MegamanX's remote `ssh-ng` store, using its canonical Zero-config host/user/key metadata and an `op read` temporary key. Force remote-only builds and fail closed for unsupported target systems or unavailable credentials.

**Tech Stack:** Bash, devenv Machines, Nix CLI, 1Password CLI, Nix runCommand tests.

**Spec:** `docs/superpowers/specs/2026-11-14-machines-build-remote-builder-design.md`

## Global Constraints

- Each `machines:build` invocation continues to require exactly one catalog machine name.
- MegamanX's configured builder supports `aarch64-darwin`; do not route other cross targets to it.
- Keep the remote store's pinned SSH host key, `nixbuilder` account, and `ssh-ng` protocol.
- Do not expose builder key contents in arguments, logs, Nix expressions, derivations, or persistent files.
- Fetch the key only for a supported cross build, use a mode-`0600` temporary key file, and remove it on success and failure. Pass the remote store through a per-command `--nix-option store`; do not change global Nix configuration.
- Do not alter deployment, plan, apply, or installed-machine configurations.

## Review Focus

- Same-system targets must still build locally without invoking `op` or the remote builder.
- Cross `aarch64-darwin` targets must use the pinned MegamanX remote store with local jobs disabled.
- Other cross targets must fail before secret resolution or build invocation.
- Missing `op`, failed key resolution, and remote build failure must fail safely and leave no temporary key file.
- Key contents must not appear in captured task logs or arguments.

---

### Task 1: Specify remote build routing and cleanup in tests

**Files:**
- Modify: `tests/test-machine-ops.sh`

**Interfaces:**
- Exercise the existing `machine-ops.sh build <machine>` entry point.
- Mock Nix catalog/current-system queries, `op read`, and the pinned `devenv build` call.

- [ ] Extend the Nix mock to return target systems and the canonical Zero builder data: MegamanX host, `aarch64-darwin`, `ssh-ng`, `nixbuilder`, parallelism/features, pinned public host key, Opnix default vault, and the existing builder-key item reference.
- [ ] Add an `op` mock that emits a fake key only to stdout and records the requested URI without recording the key value.
- [ ] Extend the devenv mock to assert that a cross build receives the pinned `ssh-ng` remote-store URI and `max-jobs = 0`, verifies the temporary key exists with fake content while the build runs, and optionally simulates build failure.
- [ ] Add cases for local build (no key lookup), cross `aarch64-darwin` build (remote builder selected and key cleaned), unsupported cross target (rejected before `op` or build), key-read failure, and build failure (key still cleaned).
- [ ] Run the focused check and confirm RED:

```sh
nix build ".#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).machines-ops" --no-link --impure
```

Expected: the new remote-build assertions fail because `machine-ops.sh build` currently invokes a plain local `devenv build`.

### Task 2: Implement fail-closed remote routing in the machine build operation

**Files:**
- Modify: `scripts/machine-ops.sh`

**Interfaces:**
- Consumes catalog target-system metadata from `machine_metadata`.
- Uses Nix evaluation of `nixosConfigurations.zero.config.nix.buildMachines`, Zero's configured default vault, and its `nixRemoteBuilderKey.reference` to obtain non-secret builder metadata.
- Uses `op read` only for a supported cross build; constructs a pinned `ssh-ng` remote-store URI and passes it with `max-jobs 0` through `devenv build --nix-option`.

- [ ] Preserve the current plain `devenv build` path when current and target Nix systems match.
- [ ] Compare the current Nix system with the target system before building. For a mismatch, fail immediately unless the target is `aarch64-darwin` and exactly one MegamanX SSH store is configured.
- [ ] Validate the canonical MegamanX host, user, protocol, target system, and public host-key pin; assemble the URL-encoded SSH store URI.
- [ ] Assemble the 1Password URI from Zero's configured default vault and existing key reference; retrieve it with `op read` directly into a mode-`0600` temporary file.
- [ ] Invoke the named `devenv build` with the temporary-key remote-store URI and `max-jobs 0`, preventing silent local fallback. Build outputs reside on MegamanX's Nix store.
- [ ] Add cleanup to the existing exit cleanup path so the temporary key is removed after successful and failed builds. Keep error messages and logs free of secret contents.
- [ ] Re-run the focused `machines-ops` check and confirm GREEN.

### Task 3: Document named cross-system build behavior

**Files:**
- Modify: `docs/how-to/run-ci-locally.md`

- [ ] Document that `machines:build` uses MegamanX for non-local `aarch64-darwin` targets and rejects other unsupported cross targets rather than falling back locally.
- [ ] Keep existing named-task examples and local-CI safety boundaries unchanged.
- [ ] Run `devenv tasks run docs:validate` if the documentation validation task is available.

### Task 4: Validate the completed change

- [ ] Run `devenv tasks run check:lint`.
- [ ] Run `devenv tasks run test:build-checks`.
- [ ] Review `jj diff` and confirm the only behavior change is in named machine builds and its tests/documentation.
