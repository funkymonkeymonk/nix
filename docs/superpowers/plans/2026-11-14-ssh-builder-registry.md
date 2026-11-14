# SSH Builder Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure nine long-lived Nix systems with unique client SSH identities so Zero and MegamanX can serve each other and the rest of the fleet as platform-specific remote builders.

**Architecture:** A named public-key registry is the source for client public keys and builder host pins. A shared cross-platform module configures remote builders and Opnix runtime private-key files, while each builder exposes a restricted Nix daemon account. Private material remains in 1Password; SecretSpec provisions the Opnix token.

**Tech Stack:** Nix flakes, NixOS, nix-darwin, Opnix, SecretSpec, OpenSSH, Jujutsu.

**Spec:** `docs/superpowers/specs/2026-11-14-ssh-builder-registry-design.md`

## Global Constraints

- Nine long-lived clients: `zero`, `drlight`, `type-nas`, `type-server`, `type-server-arm`, `type-desktop`, `Lydia`, `MegamanX`, and `wweaver`; exclude `bootstrap` and `installer-iso`.
- Zero supports `x86_64-linux`; MegamanX supports `aarch64-darwin`; do not claim native `aarch64-linux` support.
- One distinct Ed25519 client key pair per long-lived system; each builder authorizes the other eight and never itself.
- Private keys stay in the configured 1Password default vault and are materialized by Opnix to root-owned mode `0400` files outside the Nix store.
- On NixOS, `nix.buildMachines.*.sshKey` must be a string path to a local file, not a Nix path.
- Preserve Determinate Nix on Darwin: do not change `nix.enable = false`; write `/etc/nix/machines` and `/etc/nix/nix.custom.conf` with `environment.etc` instead of reading or setting managed `nix.*` options.
- Host private keys remain local; host public pins are separate and independently verified. Never trust unverified `ssh-keyscan` output.
- Preserve the user-login/signing key and Ultra Media service key. Do not glob all `.pub` files into bootstrap accounts.

## Review Focus

- Missing/duplicate/wrong client registry entries — test exact nine-system inventory, valid Ed25519 keys, and unique fingerprints.
- Self-builder loops or platform mismatches — test peer lists and builder `system` values for every client.
- Private-key leakage or store import — test secret values are references only, `sshKey` is a string path, and no private-key source files are tracked.
- Missing Opnix support/token on NixOS or Darwin — test module imports, enablement, token-file paths, and provisioning declarations for all clients.
- Builder keys leaking into bootstrap login/guest accounts — test legacy local installer uses only the explicit user-access key.

---

### Task 1: Add failing SSH builder topology tests

**Files:**
- Modify: `tests/test-ssh-authorized-keys.nix`
- Modify: `tests/test-zero.nix`
- Modify: `tests/test-lydia-migration.nix`
- Create: `tests/test-ssh-builders.nix`
- Modify: `tests/default.nix`
- Modify: `tests/test-machines-foundation.nix`
- Modify: `tests/test-machine-ops.nix`
- Modify: `tests/test-machine-ops.sh`

**Interfaces:**
- Consumes: current NixOS and Darwin configuration outputs.
- Produces: failing assertions for the exact client list, reciprocal peer topology, restricted builder users, Opnix token/key settings, and no builder-key authorization in bootstrap accounts.

- [ ] **Step 1: Write failing tests**
  Assert the exact nine client names; unique Ed25519 public keys; each of Zero and MegamanX authorizes the other eight identities; each client's remote builder list omits itself and pins the opposite builder's supported system; both builders have the restricted `nixbuilder` account; and SecretSpec/Opnix metadata is reference-only.
  Update existing authorized-key expectations to remove Lydia's accidental builder account. Add an installer regression assertion that only `monkey-ssh.pub` is copied to bootstrap `admin` and no key is copied to `guest` by default.

- [ ] **Step 2: Verify RED**
  Run the focused SSH builder test derivation and observe expected missing topology/registry failures, not evaluation syntax errors.

- [ ] **Step 3: Commit tests before implementation**
  Use `jj describe -m "test: specify reciprocal ssh builder topology"` after tracking any new test file.

### Task 2: Provision and register nine client identities

**Files:**
- Preserve: `keys/nix-remote-builder-megamanx.pub` as Zero's existing client public key
- Create: `keys/nix-builder-client-<system>.pub` for the other eight systems
- Modify: `keys/README.md`
- Create: `library/ssh-key-registry.nix`

**Interfaces:**
- Consumes: approved client inventory, the existing Zero private-key item `Nix Remote Builder Zero to MegamanX/private key`, and new Opnix items named `Nix Builder Client <system>/private key` for the other eight systems.
- Produces: `registry.clients.<system>.publicKey`, `registry.clients.<system>.secretReference`, `registry.builders.zero`, and `registry.builders.MegamanX` public metadata.

- [ ] **Step 1: Reuse Zero's existing client pair and generate eight new Ed25519 pairs**
  Keep the current Zero→MegamanX key pair as Zero's unique client identity; do not rotate it. Store each other private key in its matching Opnix SSH-key item in that machine's configured default vault; only commit its `.pub` file. Do not print or log private material. Record public fingerprints only.

- [ ] **Step 2: Obtain and verify Zero's host public key**
  Compare against an existing trusted `known_hosts` entry or the Zero local console. Do not use an unverified scan. Keep the existing MegamanX pin and represent both pins as named registry data with readable public-key files and required Nix base64 values.

- [ ] **Step 3: Implement the registry and verify RED-to-GREEN**
  Load public keys from fixed files, map each machine to its unqualified Opnix private-key reference, and define builder system/hostname/host pin. Run the focused registry tests.

- [ ] **Step 4: Commit public registry data**
  Confirm no private key or resolved SecretSpec value is tracked, then describe the change conventionally.

### Task 3: Configure shared clients and reciprocal restricted builders

**Files:**
- Create: `library/machines/remote-builders.nix`
- Modify: `library/machines/devenv.nix`
- Modify: `library/lib/mk-system.nix`
- Modify: `library/machines/catalog.nix`
- Modify: `library/machines/generated/Lydia.nix`
- Modify: `machines/zero/default.nix`
- Modify: `machines/Lydia/default.nix`
- Modify: `secretspec.toml`
- Modify: `scripts/machine-ops.sh`

**Interfaces:**
- Consumes: registry from Task 2 and catalog machine name/platform.
- Produces: per-client `nix.buildMachines`, `nix.distributedBuilds`, builder substitute setting, Opnix client-key runtime secret, and restricted builder-account authorization lists.

- [ ] **Step 1: Write tests for cross-platform Opnix and builder behavior**
  Extend Task 1 tests to require the pinned `opnix.darwinModules.default` import; enabled Opnix system secret service wherever a builder client key is required; an appropriate token path; and mode `0400`, root ownership, and a string `sshKey` path.

- [ ] **Step 2: Verify RED**
  Evaluate the focused test and confirm missing Darwin Opnix, reciprocal builder entries, and secret provisioning fail as expected.

- [ ] **Step 3: Add the shared registry-driven module**
  Configure all nine long-lived clients to use the other builder(s), with Zero `x86_64-linux` and MegamanX `aarch64-darwin`. Exclude self. On NixOS use `nix.buildMachines`; on Darwin preserve `nix.enable = false`, render `/etc/nix/machines`, and set `builders` plus `builders-use-substitutes` in `/etc/nix/nix.custom.conf`. Leave native `aarch64-linux` work local. Add each client's private key as an Opnix reference at a platform-appropriate local runtime path; keep private values out of module expressions.

- [ ] **Step 4: Configure Zero and MegamanX as restricted builders**
  Authorize all other registered clients on each host's `nixbuilder` account; trust that account only on builder hosts; retain forced Nix daemon command and disable interactive/forwarding features. On MegamanX put the Nix trust and builder settings in `nix.custom.conf`, not `nix.settings`, because nix-darwin Nix management is disabled. Remove the obsolete Lydia builder account/key/trust configuration.

- [ ] **Step 5: Enable Opnix system modules and provision its token**
  Import `opnix.darwinModules.default` for Darwin systems; enable the NixOS/Darwin system secret service on participating clients; provision `OPNIX_SERVICE_ACCOUNT_TOKEN` with SecretSpec using the documented provider route and root-only permissions. Add a narrow `BuilderClients` SecretSpec profile for `type-desktop` and `wweaver`; keep `Personal` reserved for bootstrap/installer systems, and add the token to MegamanX's custom profile.

- [ ] **Step 6: Verify green**
  Run focused builder topology, authorized-key, Zero builder, Lydia migration, machine inventory, and SecretSpec tests.

- [ ] **Step 7: Commit reciprocal builder configuration**
  Commit only after all named tests pass.

### Task 4: Fix legacy installer key selection and document operations

**Files:**
- Modify: `scripts/nixos-install.sh`
- Modify: `tests/test-ssh-authorized-keys.nix` or `tests/test-installer.sh`
- Modify: `keys/README.md`
- Create/modify: `docs/how-to/nix-remote-builders.md`

**Interfaces:**
- Consumes: `monkey-ssh.pub` as the explicit bootstrap-login key.
- Produces: bootstrap config that never authorizes builder identities as login keys; operator instructions for network access, key rotation, builder platforms, and host-pin verification.

- [ ] **Step 1: Add failing installer-scope test**
  Assert local and remote installer paths authorize only the explicit user key to the admin account and authorize no keys to `guest`; builder `.pub` files are never globbed.

- [ ] **Step 2: Verify RED**
  Run the focused shell/Nix test and confirm it fails because of the existing `.pub` glob and guest authorization.

- [ ] **Step 3: Implement explicit bootstrap key selection**
  Remove automatic enumeration of `keys/*.pub`; load only the canonical user key and do not grant it to `guest`.

- [ ] **Step 4: Document platform/network/rotation behavior**
  Describe the nine-client registry, two builder platforms, LAN/Tailscale hostname requirement, the `aarch64-linux` limitation, private-key rotation, Opnix token scope, and independently verified host-key pins.

- [ ] **Step 5: Run focused tests and commit**
  Run installer key-scope tests and the builder docs checks.

### Task 5: Full verification

- [ ] Run `devenv tasks run check:lint`.
- [ ] Run `devenv tasks run test:build-checks`.
- [ ] Run `devenv tasks run test:eval` because NixOS and Darwin configurations change.
- [ ] Review `jj diff` for private key material, unintended profile/vault changes, and builder self-loops.
- [ ] Confirm working copy status and report any verification blocked by live 1Password or host-key access.
