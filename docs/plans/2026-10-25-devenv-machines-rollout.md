# devenv Machines Deployment and Live Installer Implementation Plan

> **Note:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make devenv Machines the primary build/deploy/install workflow, backed by operation-scoped 1Password SecretSpec profiles, and provide a minimal SSH-ready USB installer target.

**Architecture:** Define each host once in a canonical Nix machine inventory. Project that inventory into devenv Machines for operator workflows and into existing flake system outputs for compatibility with nixos-rebuild, auto-upgrades, tests, and the ISO. Refactor the existing ISO into an SSH-enabled NixOS live target whose helper reports access details; perform installation from the workstation.

**Tech Stack:** Nix flakes, flake-parts, devenv 2.4.0 Machines, SecretSpec, 1Password CLI, NixOS VM tests, Jujutsu.

---

## Execution rules

- Execute tasks in order. Tasks 2–4 share central files and must not run concurrently.
- Follow RED → GREEN for each behavior: add the automated test first, run it and confirm failure, then implement the smallest change and rerun it.
- Use the approved spec as the source of acceptance criteria: `docs/superpowers/specs/2026-10-25-machines-first-deployment-design.md`.
- Do not create or guess a 1Password item/field reference for an opnix token. Implement provider profiles without embedding credentials. If a concrete secret mapping is required and its default-vault item is unknown, stop and ask the user.
- Never put resolved SecretSpec values, 1Password service-account tokens, or private SSH keys in Nix expressions, logs, the ISO, or Git.
- Nix flake evaluation reads the committed Git tree. Before pre-commit Nix checks, stage newly created source/test files as required by the repository instructions; use `--impure` only for pre-commit local feedback. After describing the JJ commit, run final validation without `--impure`.
- Create a JJ commit after each task using a conventional commit message. Do not deploy to a real host during implementation. Use disposable VMs only.

## Task 1: Pin devenv 2.4.0 and add safe SecretSpec provider profiles

**Files:**
- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `devenv.lock`
- Create: `secretspec.toml`
- Modify: `library/outputs.nix`
- Modify: `modules/roles/foundation-packages.nix` only if needed to make the installed/shell CLI use the pin consistently
- Create: `tests/test-machines-foundation.nix`
- Modify: `tests/default.nix`

**Step 1: Write failing tests**

Add checks to `tests/test-machines-foundation.nix` for:

- The root flake’s devenv input is pinned to the stable `v2.4.0` ref, not `main`.
- SecretSpec declares separate `Homelab` and `Personal` 1Password routes/profiles.
- The manifest and devenv configuration do not set resolved secret values globally or include a service-account token.

Wire the tests into `tests/default.nix` as named flake checks. Keep assertions about outcomes (the provider profiles route to the configured vaults and no value/token is embedded), not just line presence where practical.

**Step 2: Run the new checks and verify RED**

Run from the workspace root:

```sh
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machines-secret-profiles" --no-link --impure
```

Expected: failure because the pin/profile manifest and check are not yet implemented.

**Step 3: Implement the pin and manifest**

- Pin `inputs.devenv.url` to `github:cachix/devenv/v2.4.0`.
- Update `flake.lock` and `devenv.lock` deliberately; they lock distinct interfaces and both must be reviewed.
- Add SecretSpec provider routes for the existing `Homelab` and `Personal` vault defaults. Use operation-scoped SecretSpec/Machines secret resolution; do not globally expose secrets from `devenv.nix` or shell initialization.
- Make the CLI supplied by repo packages/system roles use the pinned build on each supported platform where it builds. Keep a documented fallback only if testing demonstrates a platform-specific blocker.
- Do not add an opnix service-account token reference until its exact item/field is confirmed.

**Step 4: Verify GREEN and compatibility**

Run:

```sh
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machines-secret-profiles" --no-link --impure
nix run .#devenv -- --version
nix run .#devenv -- machines --help
```

Expected: the focused check passes, the pinned CLI reports 2.4.0, and the Machines command is available. Machine discovery is verified after Task 2. Then run `devenv tasks run check:lint`.

**Step 5: Commit**

```sh
jj describe -m "feat: pin devenv machines and configure secretspec"
jj new
```
Then run the focused check and `devenv tasks run check:lint` against the committed tree.

## Task 2: Define one canonical machine inventory and generate both projections

**Files:**
- Create: `library/machines/catalog.nix`
- Create: `library/machines/devenv.nix`
- Create: `library/machines/flake-parts.nix`
- Modify: `library/machines/bootstrap.nix`
- Modify: `library/machines/cattle.nix`
- Modify: `library/machines/installer-iso.nix`
- Modify: `library/machines/zero.nix`
- Modify: `library/machines/drlight.nix`
- Modify: `library/machines/darwin.nix`
- Modify: `flake.nix`
- Create: `tests/test-machines-inventory.nix`
- Modify: `tests/default.nix`

**Step 1: Write failing projection parity tests**

Create tests asserting that:

- Every existing NixOS and Darwin configuration name is present in the catalog.
- Every catalog entry is exposed by the appropriate native flake projection and Machines projection.
- Neither projection contains a machine absent from the catalog.
- System, hostname, module list, overrides, and required special args remain present for representative NixOS and Darwin hosts.

Use existing flake-parts tests (`tests/test-flake-module.nix`, `tests/test-phase3-zero.nix`, `tests/test-phase2-cattle.nix`) as patterns. Wire the new check in `tests/default.nix`.

**Step 2: Run the parity test and verify RED**

```sh
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machines-inventory" --no-link --impure
```

Expected: fail because the catalog/projections do not exist.

**Step 3: Extract the machine records**

Move current per-machine records from the existing flake-parts machine modules into `library/machines/catalog.nix`. Preserve the complete module stacks and all current `specialArgs`, overrides, hostnames, system values, and auto-upgrade flake URLs. Do not change module behavior as part of extraction.

**Step 4: Generate the Machines and flake projections**

- Implement `library/machines/devenv.nix` to map catalog records into devenv `machines.<name>` entries with the correct role and platform.
- Implement `library/machines/flake-parts.nix` to map those same records to `nixosConfigurations`/`darwinConfigurations` using `library/lib/mk-system.nix`.
- Replace individual imports in `flake.nix` with the projection module while preserving other flake outputs.
- Ensure the installer ISO remains an output during the migration.

**Step 5: Run evaluation and parity checks**

Run the focused test, then evaluate all current system names using the repository’s existing task:

```sh
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.machines-inventory" --no-link --impure
nix eval --impure --json .#nixosConfigurations --apply builtins.attrNames
nix eval --impure --json .#darwinConfigurations --apply builtins.attrNames
```

Expected: all prior machine names evaluate, the parity test passes, and no host module has been dropped. After the task commit, run `devenv tasks run test:eval` and repeat the focused check without `--impure`.

**Step 6: Commit**

```sh
jj describe -m "refactor: generate machine outputs from canonical inventory"
jj new
```
Then rerun `devenv tasks run test:eval` and the focused parity check without `--impure`.

## Task 3: Add explicit local/remote build and deployment commands

**Files:**
- Create: `scripts/machine-ops.sh`
- Modify: `devenv.nix`
- Modify: `library/machines/catalog.nix`
- Create: `tests/test-machine-ops.sh`
- Create: `tests/test-machine-ops.nix`
- Modify: `tests/default.nix`
- Modify: `docs/reference/tasks.md`
- Modify: `docs/how-to/run-ci-locally.md`

**Step 1: Write failing command-safety tests**

Add `tests/test-machine-ops.sh` using a fake `devenv` executable in a temporary `PATH`, and expose it through a small `pkgs.runCommand` derivation in `tests/test-machine-ops.nix`. Assert that the wrapper:

- Requires an explicit command and machine name.
- Forwards only the named machine to `devenv machines ...`.
- Selects the configured SecretSpec profile for that machine (`Homelab` or `Personal`).
- Rejects an empty name and never invokes an all-machines deploy or `--yes` implicitly.

**Step 2: Run the test and verify RED**

```sh
bash tests/test-machine-ops.sh
```

Expected: fail because the wrapper does not exist.

**Step 3: Implement the wrapper and devenv tasks**

- Add a small argument-validating script for `info`, `build`, `check`, `plan`, `apply`, `deploy`, and `install` operations.
- Keep target names explicit. For destructive `install`, require an explicit target and display a disk/install warning before forwarding to devenv.
- Use `devenv` profiles or the supported SecretSpec profile override per target. Do not bake a secret into task input, environment defaults, or output.
- Add namespaced task entries in `devenv.nix` that forward validated task inputs to the wrapper. Tasks must not select every configured machine when no name is provided.
- Represent local targets explicitly, using a profile/local override rather than automatic hostname matching. Document how to supply the SSH endpoint for a freshly booted ISO target without committing a personal address.
- Use `plan`/`apply` for review-first production operations; retain interactive `deploy` for explicitly named targets.

**Step 4: Run the safety tests and CLI smoke checks**

```sh
bash tests/test-machine-ops.sh
devenv machines info
devenv tasks list
```

Expected: tests pass, machine inventory is listed, and task help does not trigger deployment.

**Step 5: Commit**

```sh
jj describe -m "feat: add explicit machines deployment commands"
jj new
```
Then rerun the focused command check and lint against the committed tree.

## Task 4: Replace the interactive ISO with the SSH-ready live target

**Files:**
- Create: `packages/installer-ready/default.nix`
- Create: `packages/installer-ready/installer-ready.sh`
- Modify: `targets/installer-iso/default.nix`
- Modify: `library/machines/installer-iso.nix`
- Modify: `library/outputs.nix`
- Modify: `tests/test-installer.sh`
- Create: `tests/test-installer-ready.sh`
- Create: `tests/test-installer-ready.nix`
- Modify: `tests/default.nix` and `tests/vm/default.nix` as required for smoke coverage
- Modify: `docs/how-to/create-installer-usb.md`

**Step 1: Write failing helper and ISO tests**

Add `tests/test-installer-ready.sh` to run the helper with stubbed system commands and assert it reports; wrap it with `tests/test-installer-ready.nix` and wire that derivation into `tests/default.nix`:

- Available network addresses without leaking unrelated environment values.
- SSH service status and the host public-key fingerprint.
- A clear workstation-side instruction to install an explicitly named machine.

Add structural/evaluation assertions that the ISO enables SSH/networking/flakes, invokes the helper automatically on the local console after boot, includes the usage text in MOTD, and does not configure a local disk-format/install action or include a private key/token.

**Step 2: Run tests and verify RED**

```sh
bash tests/test-installer-ready.sh
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.installer-ready" --no-link --impure
```

Expected: fail because the helper and new ISO settings do not exist.

**Step 3: Implement the helper**

Create `installer-ready` as a small package with explicit runtime dependencies (`iproute2`/address reporting, OpenSSH tools, and basic disk inspection). It must not perform partitioning, mount filesystems, fetch secrets, or invoke an installation command. Print the helper automatically in the booted local terminal and install the same human-readable instructions as MOTD text for SSH logins.

**Step 4: Refactor the ISO configuration**

- Keep the existing x86_64 NixOS `installation-cd-minimal` base, USB/EFI boot support, networking, flakes, and SSH service.
- Remove the interactive disko wizard/autostart path from the target ISO; the workstation’s Machines command remains the installer.
- Configure only public SSH authorized-key material according to the documented bootstrap access policy. Do not put private keys or SecretSpec values in the image.
- Keep `.#iso` and `nixosConfigurations.installer-iso` available. Preserve the old installer as a fallback until the new SSH/install workflow has passed its VM and physical smoke tests.

**Step 5: Verify helper, build, and VM boot behavior**

```sh
bash tests/test-installer-ready.sh
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.installer-ready" --no-link --impure
nix build .#iso --no-link --print-build-logs
```

Expected: helper/structural checks pass and the ISO builds on Linux. Boot it in QEMU and verify the terminal prompt, MOTD, networking, and SSH access before testing hardware.

**Step 6: Commit**

```sh
jj describe -m "feat: build ssh-ready installer live iso"
jj new
```
Then rerun the focused check and build `.#iso` without `--impure` on Linux.

## Task 5: Exercise a disposable deployment and migrate documentation

**Files:**
- Modify: `tests/vm/default.nix`
- Create: `tests/vm/machines-deploy.nix` if the existing test aggregator requires a separate module
- Modify: `tests/default.nix`
- Modify: `devenv.nix`
- Modify: `docs/how-to/create-installer-usb.md`
- Modify: `docs/tutorials/setup-your-nixos-machine.md`
- Modify: `docs/reference/tasks.md`
- Modify: `docs/explanation/testing.md`
- Modify: `tests/test-installer.sh` and installer scripts only after parity is validated

**Step 1: Write the disposable VM integration test**

Create a Linux-only test fixture that starts an SSH-accessible NixOS VM with a disposable disk and known test key. Verify a named Machines check/plan/deploy can reach it and validate the resulting generation. Never use production host names, disks, credentials, or SSH keys in this test. If the Machines 2.4 CLI cannot run the full install lifecycle in NixOS VM tests, keep the integration test at the supported build/plan/deploy boundary and document the manual fresh-host smoke step.

**Step 2: Run the test and verify RED**

```sh
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)
nix build ".#checks.${CURRENT_SYSTEM}.vm-ssh-target" --no-link --impure
```

Expected: fail until the disposable target and test wiring exist.

**Step 3: Implement integration and docs**

- Wire the test into the existing Linux-only VM test set without changing unrelated VM tests.
- Update the USB guide to describe build, safe flashing, local console output, SSH fingerprint verification, the named workstation install command, and recovery/troubleshooting.
- Update machine setup/task/testing documentation to show the Machines-first path and generated compatibility flake outputs.
- Deprecate the old custom installer/nixinate proposal only after the new path is proven; remove no fallback prematurely.

**Step 4: Run verification**

```sh
bash tests/test-machine-ops.sh
bash tests/test-installer-ready.sh
devenv tasks run check:lint
devenv tasks run test:build-checks
devenv tasks run test:eval
devenv tasks run test:all
```

Also run the disposable VM check on x86_64-linux and validate representative Darwin builds on aarch64-darwin. After describing the final JJ commit, rerun the final required checks against the committed tree without `--impure`.

**Step 5: Commit**

```sh
jj describe -m "test: validate machines deployment and update install docs"
jj new
```
Then run the final checks against the committed tree without `--impure`.

## Completion checklist

- [ ] devenv CLI is 2.4.0 on supported platforms, with locks updated and reproducible.
- [ ] All current machine systems are generated from the canonical inventory into both Machines and flake outputs.
- [ ] Named local/remote operations are available and fail closed without a target.
- [ ] SecretSpec routes to the existing `Homelab`/`Personal` vaults without global secret injection or guessed item references.
- [ ] USB ISO is minimal, SSH-ready, and prints its helper on the console and in MOTD.
- [ ] Existing VM tests and new machine/ISO tests pass; disposable deployment is proven before any production rollout.
- [ ] Legacy installer/deploy paths are retired only after the supported replacement is validated.
