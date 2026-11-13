# Centralized Cross-Platform Tailscale Implementation Plan

> **Note:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Use one catalogued Tailscale policy and Drlight's deployment-generated OAuth auth-key flow for every enabled NixOS and Darwin machine, including centralized tailnet-only Serve mappings.

**Architecture:** The machine catalog owns Tailscale enablement and tags. The shared Tailscale role owns policy options and selects native NixOS/systemd or Darwin/launchd adapters. The machine-operations wrapper generates a preauthorized, non-reusable OAuth key only for a disconnected target during an explicit deployment/apply, stages it in a restricted runtime file, and cleans it up. Bifrost no longer owns Tailscale Serve setup.

**Tech Stack:** NixOS, nix-darwin, systemd, launchd, devenv Machines, SecretSpec, Tailscale OAuth API, Nix runCommand/module evaluation tests.

---

## Execution Rules

- Use RED → GREEN for every behavior: add the automated test first, run it and verify failure, then implement the minimum change and rerun it.
- Keep all operations off live hosts. Do not run `machines:deploy`, `machines:apply`, `system:switch`, `tailscale up`, or any Tailscale API call while implementing.
- Use Jujutsu for version history. Before pre-commit Nix checks, stage new files with `git add` as required for colocated Git-flake visibility, and use `--impure` for focused local feedback. Commit source changes before final Nix flake validation; run final checks without `--impure`.
- Never print, persist in the Nix store, or log OAuth client credentials or generated auth keys. Mock credentials and keys in tests.
- Use the approved spec: `docs/superpowers/specs/2026-11-12-centralized-tailscale-design.md`.

## Task 1: Make the catalog the source of Tailscale enrollment policy

**Files:**
- Modify: `library/machines/catalog.nix`
- Modify: `library/archetypes/headless-server-nixos.nix`
- Modify: `library/archetypes/server-machine.nix` or `library/archetypes/type-server.nix` if it owns the Tailscale enablement
- Modify: `machines/zero/default.nix`
- Modify: `machines/drlight/default.nix`
- Modify: `modules/roles/tailscale.nix`
- Modify: `scripts/machine-ops.sh`
- Modify: `tests/test-machine-ops.sh`
- Modify: `tests/test-machine-ops.nix`
- Modify: `secretspec.toml`
- Create: `tests/test-tailscale-config.nix`
- Modify: `tests/default.nix`
- Modify: `tests/test-zero.nix`
- Modify: `tests/test-media-center-archetype.nix`
- Modify: `tests/test-lydia-migration.nix`

**Step 1: Add failing configuration assertions**

Create checks for the intended machine policy:

- `type-nas`, `type-server`, `zero`, `drlight`, and `MegamanX` have Tailscale explicitly enabled in their catalog overrides.
- All five use `tag:home-lab`; Drlight additionally uses `tag:media-center`.
- `type-server-arm` remains Tailscale-disabled.
- No enabled host relies on the old `authKeyOpnixItem`/static-key path or the old per-host `authKeyMode = "opnix"` behavior.
- MegamanX's SecretSpec profile references the existing Tailscale OAuth client ID and secret through the approved `opnix` provider; assert references only, never resolve values.
- Machine-operations metadata reads catalogued Tailscale enablement/tags; a named NixOS deploy uses OAuth for enabled targets and skips auth-key generation for disabled targets.

Wire the check into `tests/default.nix`. Extend `tests/test-machine-ops.sh` with mocked enabled/disabled NixOS deployment cases. Update the existing Zero/media-center/MegamanX assertions to describe the new OAuth behavior. Run the focused checks and confirm RED before changing implementation. Do not use a live target.

**Step 2: Centralize enablement and tags in the catalog**

Set `myConfig.tailscale.enable` and `authKeyTags` in each enabled machine's catalog `overrides`. Use `tag:home-lab` as the shared default for ordinary hosts and preserve Drlight's two-tag policy. Remove duplicate enablement and static auth-key references from the host modules/archetypes. Preserve the disabled `type-server-arm` override.

**Step 3: Remove static-key enrollment configuration**

Update `modules/roles/tailscale.nix` options so the only enrollment method is deployment-generated OAuth. Remove the static Opnix auth-key item option, the NixOS Opnix Tailscale key declaration, and any `opnix-secrets.service` dependency that exists only for that key. Keep shared tags, exit-node, and advertised-route options. Give the common tag option the approved `tag:home-lab` default where that does not override Drlight.

Add OAuth credential references to `[profiles.MegamanX]` in `secretspec.toml`, matching the existing Opnix-profile OAuth references and provider. Do not add any resolved value. Existing Opnix-profile machines continue to use that profile.

Update `scripts/machine-ops.sh` to branch on the catalogued Tailscale-enabled flag instead of the removed `authKeyMode`. For this task, retain the existing NixOS-only deploy handoff; Task 3 removes the Darwin restriction and adds apply support. Extend the machine-operations mocks to prove enabled NixOS targets use generated OAuth keys and disabled targets do not.

**Step 4: Run focused tests and inspect the diff**

Run the new configuration check and affected existing checks. Confirm the Tailscale enablement/tag values have one catalog source, the wrapper dispatches by catalogued enablement, and no static Tailscale key secret is generated. Expected: all focused tests pass; no live machine is contacted.

## Task 2: Implement native NixOS and Darwin authentication and central Serve policy

**Files:**
- Modify: `modules/roles/tailscale.nix`
- Create: `modules/nixos/tailscale.nix`
- Modify: `modules/nixos/base.nix`
- Create: `modules/services/tailscale/darwin.nix`
- Create: `modules/services/tailscale/up-arguments.nix`
- Modify: `library/archetypes/base-darwin.nix`
- Modify: `modules/services/bifrost/darwin.nix`
- Modify: `library/machines/catalog.nix`
- Modify: `tests/test-tailscale-config.nix`
- Modify: `tests/test-bifrost.nix`
- Modify: `tests/test-lydia-migration.nix`

**Step 1: Add failing platform-adapter tests**

Assert that:

- NixOS still defines `services.tailscale.enable` and an idempotent `tailscale-autoconnect` systemd service which consumes `/run/devenv/tailscale-auth-key` only when Tailscale is not already running.
- Darwin enables the Tailscale daemon and defines a launchd auth adapter that waits for `tailscaled`, watches the staged key path, calls `tailscale up --auth-key=file:…` only when backend state is `NeedsLogin`, and removes the key after use. Other or unknown states fail closed without consuming the key. The generated key is never placed in a derivation or logged.
- MegamanX declares the Bifrost Serve mapping under `myConfig.tailscale.serve`; the mapping targets `http://127.0.0.1:8081`, checks `http://127.0.0.1:8081/v1/models`, and does not enable Funnel.
- Bifrost no longer creates its own `bifrost-tailscale-serve` daemon or Tailscale CLI script.

Run the focused test and verify RED.

**Step 2: Keep the NixOS adapter on the deployment key file**

Keep the NixOS systemd one-shot connection behavior in `modules/nixos/tailscale.nix`, imported by the shared NixOS base. It consumes `/run/devenv/tailscale-auth-key` only when Tailscale is disconnected and removes the one-time key after use; the deployment controller remains a second cleanup boundary.

**Step 3: Add the Darwin daemon/auth adapter**

Implement the Darwin adapter in `modules/services/tailscale/darwin.nix` and import it from the Darwin base so only Darwin systems receive launchd definitions. It owns `services.tailscale.enable`, the persistent `tailscaled` daemon, and a privileged launchd one-shot that watches `/tmp/devenv-tailscale-auth-key`. It must wait for the daemon/API to become ready, exit harmlessly if no key is staged, authenticate only from `NeedsLogin`, avoid re-authenticating a running node, fail closed on any other/unknown state without consuming the key, and remove it after success. The deployment wrapper writes this runtime-only file with mode `0600`; the deployment SSH user owns it and the privileged daemon can read it. `modules/services/tailscale/up-arguments.nix` keeps platform adapters' `tailscale up` flags consistent. Verify the path and launchd `WatchPaths` behavior in tests. Do not embed credentials in Nix-generated scripts.

**Step 4: Move Bifrost Serve configuration into Tailscale policy**

Add an attribute-set option for Serve mappings under `myConfig.tailscale`. Configure MegamanX's Bifrost mapping in its catalog overrides. Generate a Darwin launchd service from this shared option that waits for both a Tailscale IP and the mapping's readiness URL before running `tailscale serve --bg --http=<port> <target>`. Keep Bifrost loopback-bound and remove its existing Serve script/options/daemon. Do not configure Funnel.

**Step 5: Run focused checks**

Run the platform module tests and Bifrost tests. Shell-check every generated launcher with `bash -n`. Verify the generated test config retains exactly one Serve owner and the NixOS adapter remains unchanged in behavior.

## Task 3: Extend named deployment/apply OAuth key handoff to Darwin and all enabled hosts

**Files:**
- Modify: `scripts/machine-ops.sh`
- Modify: `scripts/tailscale-oauth-authkey.sh` only if tests expose a necessary change
- Create: `scripts/tailscale-darwin-autoconnect.sh`
- Create: `tests/test-tailscale-darwin-autoconnect.sh`
- Modify: `tests/test-machine-ops.sh`
- Modify: `tests/test-machine-ops.nix`
- Modify: `modules/services/tailscale/darwin.nix`
- Modify: `tests/test-tailscale-config.nix`
- Modify: `tests/default.nix`

**Step 1: Add failing machine-operations tests**

Extend the fake-command shell tests to cover both NixOS and Darwin targets and both `deploy` and reviewed `apply`:

- A target reporting `Running` receives no generated key or staging operation; an empty, unparseable, or unsupported backend state aborts before key generation and activation.
- A disconnected enabled target gets a key from the target's SecretSpec profile with that target's tags.
- A target without Tailscale enabled does not generate a key.
- Missing OAuth fields, missing tags, malformed target metadata, or failed staging abort before activation.
- NixOS staging remains `/run/devenv/tailscale-auth-key`; Darwin staging uses `/tmp/devenv-tailscale-auth-key`, mode `0600`, exactly matching the path watched by the launchd adapter.
- Staged keys are removed after the target reports `Running`, and after deployment/apply failure or timeout; neither key nor OAuth client secret appears in captured logs.
- The Darwin adapter retries transient `Starting`/unavailable status, invokes `tailscale up` only for `NeedsLogin`, and does not consume the key for any other backend state.
- Apply activation failure has an explicit cleanup test, in addition to deploy failure.
- The previous blanket rejection of Darwin OAuth enrollment is removed without weakening explicit target/plan validation.

Run the focused shell test and verify RED.

**Step 2: Make catalog metadata sufficient for safe decisions**

Update `machine_metadata()` to return the catalogued Tailscale-enabled flag, platform, SecretSpec profile, and tags. Keep metadata evaluation free of SecretSpec secret resolution. Since catalog entries now explicitly own enablement/tags, do not infer enabled state by searching module text or defaulting all machines to Tailscale-enabled.

**Step 3: Factor key generation and staging around explicit target operations**

Create a helper in `scripts/machine-ops.sh` that:

1. Checks remote `tailscale status --json` using strict SSH settings and parses the response strictly.
2. Returns without generating a key if backend state is `Running` or the target is not Tailscale-enabled; fails before generation if the command fails, JSON is malformed, or state is empty/unsupported.
3. Resolves OAuth credentials only through the target's scoped SecretSpec profile and invokes `scripts/tailscale-oauth-authkey.sh` with the catalogued machine name and validated tags.
4. Stages the key via SSH to the platform-specific restricted runtime path without putting it in command arguments or output.
5. Installs a shell `trap` so cleanup runs after the named `deploy` or `apply` whether activation succeeds or fails. If a key was staged and activation succeeds, wait for the target's Tailscale backend state to become `Running` before cleanup; fail with a clear timeout if it does not become connected in the bounded wait.

Call the helper for both `deploy` and `apply`, after plan-machine validation and before activation. Preserve existing behavior for other operations and keep `deploy-auto` delegating to the named deploy path.

**Step 4: Run the focused tests and review generated command behavior**

Run `bash tests/test-machine-ops.sh` and the corresponding Nix check. Inspect the shell traces from mocks only; verify they contain no simulated secret values. Confirm no real SSH connection or Tailscale API call occurred.

## Task 4: Update enrollment guidance and run repository validation

**Files:**
- Modify: `modules/nixos/tailscale.nix` (guard the adapter when the shared Tailscale role/options are absent)
- Modify: `docs/how-to/enroll-megamanx-in-tailscale.md`
- Modify: `docs/reference/options.md` only via the repository's generator if needed
- Modify: `tests/test-tailscale-config.nix`
- Modify: `tests/test-zero.nix` (replace stale assertions tied to the removed static Opnix adapter)

**Step 1: Add failing regression and documentation assertions**

Add an evaluation regression test for importing the NixOS Tailscale adapter through a minimal `modules/nixos/base.nix` context where `myConfig.tailscale` is absent. It must evaluate successfully with the adapter disabled and must not define a Tailscale service. Update Zero's Tailscale tests to inspect `modules/nixos/tailscale.nix` for the deployment key path and keep the shared-role check focused on the absence of Opnix coupling. Confirm RED against the current unguarded adapter and stale Zero expectations. Guard missing policy/options with an empty disabled policy; do not mask failures when Tailscale is explicitly enabled.

Update automated text checks, if an existing docs test covers this guide, to reject manual `sudo tailscale up` enrollment and require the named deployment-generated OAuth workflow. Keep actual deployment commands review-first and do not include secrets.

**Step 2: Fix the disabled-adapter evaluation regression and rewrite the enrollment guide**

Guard `config.myConfig.tailscale` with a disabled default when it is absent so minimal NixOS module stacks do not fail evaluation. Then document that OAuth keys are generated for the named machine during deployment/apply, with host tags from the catalog, and that the auth key is temporary. Explain how to check Tailscale state and Bifrost Serve after activation. Remove the old interactive-login flow.

**Step 3: Run focused tests, lint, and build checks**

After staging newly created test files and committing the implementation changes as required by repository policy, run:

```sh
devenv tasks run check:lint
devenv tasks run test:build-checks
devenv tasks run test:eval
```

Run `devenv tasks run test:all` when the platform permits. On Linux, report Darwin build/evaluation limitations rather than claiming Darwin validation passed. Do not deploy any target as part of these checks.

**Step 4: Inspect final changes and task tracking**

Use `jj status` and `jj diff` to verify only intended files changed. Confirm there are no resolved credentials, generated auth keys, ignored endpoint files, or accidental service operations in the diff. Mark the yak done only after the tests and diff review pass, then sync yaks.
