# Generic Bifrost Opnix Credential Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize Bifrost virtual-key creation by name, create its setup-token item, and align MegamanX's admin references with the Login item now in Opnix.

**Architecture:** Rename the Zero-specific helper to `scripts/create-bifrost-vk.sh`, accept a validated `--key-name`, and retain the Zero task as a compatibility alias. Add a separate `scripts/create-bifrost-setup-token.sh` because setup tokens are not `sk-bf-` virtual keys. Update MegamanX's admin references to the moved `Bifrost Admin` Login item, keeping references unqualified and Opnix as the default vault.

**Tech Stack:** Bash, Nix/Devenv tasks, OpenSSL, `jq`, 1Password CLI.

**Spec:** `docs/superpowers/specs/2026-11-27-bifrost-generic-vk-design.md`

## Global Constraints

- Generate virtual keys as `sk-bf-` plus 32 random bytes encoded as 64 lowercase hexadecimal characters.
- Store virtual keys in the concealed `credential` field of `Bifrost <keyName> API Key` in MegamanX's configured default vault.
- Generate setup tokens as 32 random bytes encoded as 64 lowercase hexadecimal characters without an `sk-bf-` prefix; store in `Bifrost Setup Token/credential`.
- Keep `secrets:create-bifrost-zero-vk` as a compatibility alias using `keyName=Zero`.
- Use unqualified Opnix references `Bifrost Admin/username`, `Bifrost Admin/password`, and `Bifrost Setup Token/credential`.
- Require `confirm=true`, refuse active or archived same-title items, and do not overwrite or rotate.
- Use mode-0700 temporary directories and mode-0600 secret-bearing files; clean them on every exit.
- Never print or log secret values, pass them in command arguments/environment, or place them in the Nix store.
- Do not deploy or restart Bifrost from either credential-creation task.

## Review Focus

- Empty, whitespace-only, and newline-containing key names must fail before Nix/OpenSSL/1Password calls; test in Task 1, Step 1.
- `keyName=OpenChamber` must create `Bifrost OpenChamber API Key`; test in Task 1, Step 1.
- The Zero compatibility task must still create `Bifrost Zero API Key`; test in Task 1, Step 1.
- The setup token must be exactly 64 lowercase hex characters without an `sk-bf-` prefix; test in Task 2, Step 1.
- MegamanX admin references must use the moved Login item's username/password fields; test in Task 2, Step 1.
- Confirmation failure, duplicate active/archived items, CLI errors, cleanup, and secret-output/environment protection must remain covered; test in Tasks 1 and 2, Step 1.

---

### Task 1: Generalize virtual-key creation

**Files:**
- Rename: `scripts/create-bifrost-zero-vk.sh` → `scripts/create-bifrost-vk.sh`
- Modify: `devenv.nix`
- Rename: `tests/test-bifrost-zero-vk.nix` → `tests/test-bifrost-vk.nix`
- Rename: `tests/test-bifrost-zero-vk.sh` → `tests/test-bifrost-vk.sh`
- Modify: `tests/default.nix`
- Modify: `docs/reference/tasks.md`

**Interfaces:**
- Generic task: `devenv tasks run secrets:create-bifrost-vk --input keyName=OpenChamber --input confirm=true`.
- Compatibility task: `devenv tasks run secrets:create-bifrost-zero-vk --input confirm=true`.
- Script CLI: `scripts/create-bifrost-vk.sh --key-name OpenChamber --confirm`.

- [ ] **Step 1: Write failing tests and register the check.** Verify the generic task rejects missing/false confirmation before side effects, passes `OpenChamber` as `--key-name`, creates the exact item title, rejects empty/newline names before side effects, and retains the Zero alias. Keep assertions for default-vault resolution, archived duplicate protection, secure file modes, cleanup, and no secret in stdout/stderr/arguments/environment/logs. Register the focused check as `bifrost-vk-creation` in `tests/default.nix` so the RED test is runnable before implementation.
- [ ] **Step 2: Run the focused check and confirm RED.** Run `nix build .#checks.x86_64-linux.bifrost-vk-creation --no-link --impure`. Expected: FAIL because the generic task and name parameter are not implemented.
- [ ] **Step 3: Generalize the script.** Rename the helper, require `--key-name <name> --confirm`, validate the name, derive `Bifrost <keyName> API Key`, resolve MegamanX's configured default vault, and preserve private-template handling and no-overwrite behavior.
- [ ] **Step 4: Register generic and compatibility tasks.** Add `secrets:create-bifrost-vk` with `keyName=""` and `confirm=false`; keep `secrets:create-bifrost-zero-vk` as a wrapper with fixed name `Zero`. Both tasks enforce confirmation.
- [ ] **Step 5: Update task documentation.** Document the OpenChamber example, Zero compatibility command, and no-deploy behavior.
- [ ] **Step 6: Run the focused check and confirm GREEN.** Run `nix build .#checks.x86_64-linux.bifrost-vk-creation --no-link --impure`. Expected: PASS.

### Task 2: Generate the setup token and align admin references

**Files:**
- Create: `scripts/create-bifrost-setup-token.sh`
- Create: `tests/test-bifrost-setup-token.nix` and `tests/test-bifrost-setup-token.sh`
- Modify: `devenv.nix`
- Modify: `library/machines/catalog.nix`
- Modify: `tests/test-tailscale-config.nix`
- Modify: `tests/default.nix`
- Modify: `docs/reference/tasks.md`

**Interfaces:**
- Task: `devenv tasks run secrets:create-bifrost-setup-token --input confirm=true`.
- Script CLI: `scripts/create-bifrost-setup-token.sh --confirm`.
- MegamanX references the moved Login item as `Bifrost Admin/username` and `Bifrost Admin/password`; the shared helper prefixes `Opnix`.

- [ ] **Step 1: Write failing tests and register the check.** Assert the catalog uses the moved admin fields. Add mocked setup-token tests verifying confirmation, title `Bifrost Setup Token`, `API_CREDENTIAL` category, concealed `credential`, 64 lowercase hex characters without a prefix, duplicate/archived refusal, secure modes, cleanup, no output/environment leak, and CLI failure handling. Register `bifrost-setup-token` in `tests/default.nix`.
- [ ] **Step 2: Run focused checks and confirm RED.** Run `nix build .#checks.x86_64-linux.bifrost-setup-token --no-link --impure` and `nix build .#checks.x86_64-linux.tailscale-darwin-autoconnect --no-link --impure`. Expected: FAIL because the setup-token task and admin-reference changes are absent.
- [ ] **Step 3: Implement the setup-token creator.** Generate 32 random bytes as 64 lowercase hex characters, without `sk-bf-`; create an Opnix API Credential in the concealed `credential` field, refusing an existing active or archived item.
- [ ] **Step 4: Register the task and update MegamanX references.** Add the confirmation-gated task and change admin references to `Bifrost Admin/username` and `Bifrost Admin/password` without hard-coding a vault.
- [ ] **Step 5: Update task documentation.** Document that setup tokens differ from virtual keys and that creation does not activate Bifrost.
- [ ] **Step 6: Run focused checks and confirm GREEN.** Run the checks from Step 2 with `--impure`; both must pass.
- [ ] **Step 7: Commit the implementation.** Run `jj describe -m "feat: generalize Bifrost Opnix credential creation"` and `jj new`.

### Task 3: Create the Opnix items and apply the reviewed MegamanX configuration

**Files:** No additional tracked files; the tasks create the Opnix items and a reviewed machine plan activates the committed configuration.

- [ ] **Step 1: Verify 1Password authorization and admin-item metadata.** Confirm the Opnix `Bifrost Admin` Login item contains username and password fields using metadata only. If authorization is dismissed or either field is absent, stop and ask; do not print field values.
- [ ] **Step 2: Create the OpenChamber virtual-key item.** Run `devenv tasks run secrets:create-bifrost-vk --input keyName=OpenChamber --input confirm=true`; verify title/category only, never read the `credential` value.
- [ ] **Step 3: Create the setup-token item.** Run `devenv tasks run secrets:create-bifrost-setup-token --input confirm=true`; verify title/category only, never read the `credential` value.
- [ ] **Step 4: Validate the committed tree.** Run `devenv tasks run check:lint`, `devenv tasks run test:eval`, focused checks without `--impure`, and `devenv tasks run test:build-checks`. Report the known unrelated `workspace-switch` failure if it persists.
- [ ] **Step 5: Plan and review MegamanX only.** Run `devenv tasks run machines:plan --input machine=MegamanX`; inspect the saved plan, confirm it contains only MegamanX, and review the generation and package diff.
- [ ] **Step 6: Apply and verify.** Apply only that reviewed plan. If Devenv apply fails for non-interactive sudo, use the previously authorized direct SSH activation of the exact reviewed generation. Verify the admin/setup/OpenChamber secret files by presence/metadata only and check Bifrost health without reading secret values. Do not touch Drlight.
