# Machines-First Deployment, Testing, and Installer Design

**Status:** Approved for implementation (2026-10-25)  
**Decision:** Make devenv Machines the primary operator interface and machine inventory projection; retain generated flake outputs as compatibility interfaces.  
**Scope:** devenv upgrade, local/remote deployment, SecretSpec backed by 1Password, local VM testing, and a minimal SSH-ready live ISO for fresh hosts.

## Goals

- Make it easy to build, review, deploy, and test this Nix system from one devenv workflow.
- Use devenv Machines for local and remote NixOS/nix-darwin deployments over SSH.
- Keep machine definitions in one source and avoid drift between deployment and flake builds.
- Use SecretSpec with 1Password for operator/bootstrap secrets without putting secret values in Git or the Nix store.
- Build a small bootable NixOS live ISO that exposes a fresh host as an SSH target for workstation-controlled installation.
- Preserve automated evaluation, build, VM tests, system auto-upgrade, and installer outputs during migration.

## Non-goals

- Replacing opnix as the runtime secret manager on installed machines.
- Baking 1Password tokens, private SSH keys, or resolved secrets into the ISO or Nix store.
- Making the ISO partition or install a system by itself. Installation remains controlled by the workstation through devenv Machines.
- Removing native `nixosConfigurations`/`darwinConfigurations` outputs while current rebuild, auto-upgrade, and installer workflows depend on them.
- Deploying all configured hosts implicitly.

## Current constraints and findings

- The installed CLI reports devenv 2.2.1. The project’s `flake.lock` pins devenv to a September 18 commit; Machines was released in devenv 2.4.0 on September 24, 2026. The project’s separate `devenv.lock` also pins its module inputs independently.
- The root flake uses flake-parts to expose NixOS and Darwin configurations. `library/lib/mk-system.nix` wraps the platform system constructors. Existing machine definitions live in flake-parts modules.
- `nixosConfigurations` are consumed by `nixos-rebuild`, NixOS auto-upgrade flake URLs, tests, and the installer ISO. Machines defines normal NixOS/nix-darwin modules for build/deploy; it does not itself replace these native flake outputs.
- The repository already has `.#iso`, an `installer-iso` configuration, and an interactive installer that partitions disks. This is a distinct install path and will be simplified/replaced after the Machines flow is proven.
- Existing NixOS VM tests boot test configurations, not the full production host configurations. They remain valuable and should be retained.
- NixOS hosts explicitly use the `Homelab` vault in some targets; the shared option defaults to `Personal`. SecretSpec must provide profiles/routes aligned with each host’s existing `myConfig.onepassword.defaultVault`.

## Architecture

### Canonical machine inventory and projections

Create a single canonical machine inventory in the repository. It records each machine’s platform/system, module composition, module arguments and overrides, deployment metadata, and optional disk/install metadata. It must be possible to consume this inventory from both the devenv configuration and the flake-parts output layer.

- `devenv.nix` (or a focused imported module) projects the inventory into `machines.<name>` and is the primary interface for machine builds, reviews, installs, and deployments.
- The flake-parts layer projects the same records into `nixosConfigurations` and `darwinConfigurations`. These are generated compatibility outputs, not a second hand-maintained host inventory.
- Preserve current machine names and output semantics where possible so auto-upgrades and existing Nix commands continue to resolve the same configurations.
- Preserve shared module arguments (`inputs`, `mkUser`, and current helper libraries) and platform-specific module behavior during extraction.

This is Machines-first operationally, while retaining the Nix flake interface required by the installed systems. A future removal of those outputs would require a separate design for the auto-upgrade and installer consumers.

### devenv version and CLI

- Pin devenv to the latest stable release selected for this migration: `v2.4.0`, not `main`.
- Update both the project’s devenv input locks and the root flake lock deliberately; they serve separate roles.
- Make the CLI exposed by this repository’s development environment and system package outputs use the pinned version where supported. Keep a platform fallback only if the pinned package cannot be built or tested on that platform.
- Verify `devenv --version`, `devenv machines info`, machine evaluation/build, the existing devenv tasks, and the repository’s lock-update behavior on Linux and macOS.

Machines is experimental in devenv 2.4. Keep deployments explicit and migrate in stages.

### Deployment interface

- Expose named local and remote machine targets. Local aliases must be explicit; do not silently infer an installation target from the current hostname.
- Remote targets use SSH. NixOS deployment requires root SSH; nix-darwin requires an administrator with passwordless sudo. Use SSH agent access and preserve host verification appropriate to reviewed deployments.
- Provide clear task wrappers for listing, building, checking, planning/applying, installing, and deploying a named machine. A deploy command without a target must fail with usage/help rather than deploying the fleet.
- Prefer `devenv machines plan` and `apply` for production changes. Keep `deploy` available for reviewed interactive use. Do not use `--yes` in default workflows.
- Configure health checks and rollback windows for NixOS where useful. Document that nix-darwin and home-manager activations do not have the same NixOS rollback behavior, and a multi-machine rollout is not transactional.
- Allow builds from macOS only when a compatible builder is configured. Document that Linux machine builds may require an x86_64-linux builder from an aarch64-darwin workstation.

### SecretSpec and 1Password

- Add a committed `secretspec.toml` declaring deployment/bootstrap secret names and 1Password provider routes. Use SecretSpec through operation-scoped runtime commands or the Machines install-secret integration; do not globally inject resolved secrets into `devenv.nix` evaluation or the shell environment.
- Define profiles/providers following each machine’s configured default vault: `Homelab` for machines that explicitly select it and `Personal` where the shared default applies. Select the matching profile for each machine operation; do not substitute a cross-vault item reference.
- Use 1Password desktop-app integration for interactive local development. For headless automation, accept a service-account token only through an external credential source/environment; never place it in the manifest, Nix expression, command arguments, logs, or ISO.
- Use SecretSpec for operator-side deployment and fresh-host bootstrap credentials. Resolve credentials at run time and expose them only to the operation that needs them. Where a fresh install needs to transfer a secret, use the Machines-supported secret transfer mechanism and keep it out of derivations and build outputs.
- Keep opnix for installed-machine runtime secrets, including service credentials fetched by system services. SecretSpec does not replace that lifecycle.
- Do not invent an item/field reference for the opnix service-account token. Add a mapping only after the correct existing item/field is confirmed to be in the machine’s default vault; otherwise ask the user to move it or explicitly change the machine’s default vault.

### SSH-ready live ISO

Refactor the existing `installer-iso` configuration and `.#iso` output into a minimal, x86_64-linux NixOS live target for fresh hardware.

- Boot to an SSH-enabled NixOS live environment with networking, Nix flakes, basic disk/hardware inspection tools, and a small `installer-ready` helper. Do not include the full development shell or a second local partition/install workflow unless later required.
- The helper reports network interfaces and usable addresses, SSH service status, and the SSH host-key fingerprint, then prints clear controller-side instructions for installing a named machine. It does not format disks or install a system.
- Automatically print the helper output and next-step prompt in the local terminal after boot. Also show durable usage instructions in the MOTD so they are available to SSH users.
- The operator boots the USB, uses the reported SSH endpoint, and runs the named `devenv machines install` workflow from the workstation. The workstation remains responsible for machine selection, SecretSpec/1Password access, review, and installation.
- The image contains no private keys, 1Password tokens, resolved SecretSpec values, or other machine secrets. Configure only public SSH access material. Do not make the ISO accept arbitrary SSH access without an explicit, documented policy.
- Keep the existing `.#iso` package name where practical. Build it on Linux; provide a remote-builder/CI path for macOS users and document safe USB flashing with an explicit device-selection warning.
- Deprecate the current interactive ISO installer and standalone installer only after the new SSH/Machines flow has been tested end to end. Preserve an escape route until then.

## Workflow examples

The exact task names and target profile names will be finalized during implementation. The intended sequence is:

```sh
# Inspect machine inventory without contacting a target
devenv machines info

# Build a named machine locally
devenv build machines.<name>

# Check and review a named remote target
devenv machines check <name>
devenv machines plan <name>
devenv machines apply <plan-id>

# Or perform an explicitly named interactive deployment
devenv machines deploy <name>

# Build the live ISO on a Linux builder
nix build .#iso
```

For a fresh host, boot the ISO, read the address and fingerprint printed by `installer-ready`, then run the named install operation from the workstation. The ISO MOTD/terminal text must show the actual supported command form and any required local profile/target override after the implementation verifies the Machines CLI syntax.

## Migration phases and acceptance criteria

### Phase 1: devenv and SecretSpec foundation

- Pin devenv 2.4.0 and update both lockfiles.
- Add 1Password provider profiles matching current `Homelab`/`Personal` defaults.
- Verify no secret value or service-account token is present in tracked files, Nix store outputs, or task logs.
- Existing lint, eval, and build checks pass; `devenv --version` reports the selected version on supported systems.

### Phase 2: canonical inventory and compatibility projections

- Define every current NixOS/nix-darwin system from one inventory.
- Generate both devenv Machines declarations and native flake outputs from the inventory.
- Preserve current configuration names, module imports, special arguments, auto-upgrade URLs, and package/installer outputs.
- Add structural/evaluation tests that detect an inventory entry missing from either projection or a projection defining an unregistered machine.

### Phase 3: local and remote Machines operations

- Add explicit named local and SSH remote targets; no default all-host deployment.
- Add task/help wrappers and profile selection for the appropriate 1Password vault.
- Locally build representative Darwin and NixOS machine outputs; remotely exercise plan/apply/deploy on a disposable NixOS VM.
- Confirm NixOS rollback/health-check status behavior and document platform limitations before migrating production targets.

### Phase 4: USB live target

- Simplify the existing installer ISO into the SSH-ready target and include the helper.
- Add tests for ISO evaluation/build, helper output, SSH/network configuration, terminal-on-boot instructions, and MOTD instructions.
- Boot the image in a QEMU smoke test; verify the controller can SSH to it and complete the supported fresh-host flow against a disposable VM.
- Test one physical USB boot before using it on production hardware. Installation tests must use disposable disks/VMs because disk provisioning is destructive.

### Phase 5: migration and cleanup

- Migrate all current systems and update documentation/tasks to the Machines-first path.
- Keep flake outputs as generated compatibility interfaces.
- Remove duplicate legacy deployment/install scripts only after the new flow meets the acceptance criteria and the user approves removal.

## Risks and mitigations

- **Experimental CLI/API:** pin a release, add eval/build smoke tests, and keep rollback to the previous flake workflow during migration.
- **Accidental destructive install:** require an explicit machine and target, review disk IDs/configuration, and test exclusively on disposable systems before production.
- **SSH bootstrap access:** use explicit public-key policy and display the host fingerprint; never bake private credentials into the ISO.
- **Secret leakage:** run SecretSpec only at operation time, avoid secrets in Nix evaluation/environment globals, and verify the ISO/store closure has no secret material.
- **Platform/build mismatches:** use explicit machine systems and a configured Linux builder for incompatible cross-platform builds.
- **Split deployment activation:** document partial success when NixOS and Home Manager or multiple machines are applied separately; add health checks where supported.
- **Configuration drift:** keep a single inventory and test parity of both generated projections.

## References

- [devenv Machines](https://devenv.sh/machines/)
- [devenv 2.4: Machines](https://devenv.sh/blog/2026/09/24/devenv-24-machines/)
- [SecretSpec integration in devenv](https://devenv.sh/integrations/secretspec/)
- [SecretSpec 1Password provider](https://secretspec.dev/providers/onepassword/)

## Approval boundary

The user approved this design on 2026-10-25, including Machines-first operation with generated flake compatibility outputs, per-machine 1Password vault profiles, and the SSH-ready ISO with a boot-time terminal prompt. Exact SecretSpec item/field references and any change to a machine's configured 1Password default vault remain user-controlled and are not assumed. Fresh-host installation must remain fail-closed until the real bootstrap secret reference is confirmed in the machine's default vault.
