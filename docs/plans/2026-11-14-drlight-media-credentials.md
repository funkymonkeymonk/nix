# Drlight Media-Service Credentials Implementation Plan

> **Note:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Drlight's six media-service login identities use the username/password fields in its Opnix vault without placing secret values in the Nix store.

**Architecture:** Keep the current native NixOS services and use Nixarr-style post-start reconciliation. Radarr, Sonarr, and Lidarr use their existing API-key-driven reconciler; Bazarr uses its existing API settings reconciler; Mylar3 uses the existing runtime INI renderer; Jellyfin authenticates with the current declared admin credentials and verifies the account is an administrator. Keep Transmission, staging, and remote-path mapping unchanged.

**Tech Stack:** NixOS modules, Opnix runtime secret files, Python standard library, existing Nix evaluation checks and HTTP fake-server tests.

---

## Global Constraints

- Scope is Radarr, Sonarr, Lidarr, Bazarr, Mylar3, and Jellyfin only.
- Use Drlight's default Opnix vault and unqualified references. The item names are `Radarr`, `Sonarr`, `Lidarr`, `Bazaar` (the 1Password title), `Mylar3`, and `Jellyfin`.
- Password fields are `password` on each item's `Radarr`, `Sonarr`, `Lidarr`, `Bazaar`, `Mylar3`, and `Jellyfin` records. Assume each item also has a `username` field.
- Keep credential values out of Nix expressions, the Nix store, process arguments, logs, and tests. Tests use synthetic values only.
- Do not edit application databases directly, weaken authentication, or change seedbox Transmission/staging behavior. Deployment is a separate, explicitly authorized operation.
- Keep login reconciliation idempotent and fail safely on unavailable/empty secrets or rejected credentials.
- Follow TDD: write the behavioral test, run it and observe the expected failure, implement the minimal fix, and rerun tests.

### Task 1: Declare restricted Opnix credentials and service ordering

**Files:**
- Modify: `tests/test-media-center-archetype.nix`
- Modify: `modules/nixos/media-app-reconciliation.nix`
- Modify: `modules/nixos/media-management.nix`
- Modify: `modules/nixos/media-config.nix` only if the Jellyfin reconciler must be attached there

**Steps:**
1. Add Nix evaluation assertions for all six unqualified references, runtime-only file paths, root ownership, `media-management-secrets` group access, mode `0440`, and each service/reconciler's Opnix ordering.
2. Run the focused media-management check with `--impure`; confirm it fails because the declarations are absent.
3. Add the six Opnix secret declarations and wire only file paths into service/reconciler configuration. Give only the relevant service accounts/reconciliation units access to the secret group.
4. Ensure the post-start units wait for both their application and `opnix-secrets.service`; preserve existing Forms authentication and current service boundaries.
5. Rerun the focused check and confirm it passes.

### Task 2: Reconcile Arr and Bazarr login settings through their APIs

**Files:**
- Modify: `tests/test_media_app_reconciliation.py`
- Modify: `modules/nixos/scripts/media_api_reconcile.py`
- Modify: `modules/nixos/scripts/servarr_reconcile.py`
- Modify: `modules/nixos/scripts/bazarr_reconcile.py`
- Modify: `modules/nixos/media-app-reconciliation.nix`

**Steps:**
1. Extend the fake Arr API and add tests proving the declared username/password are sent to the host configuration endpoint, Forms auth remains enabled, password confirmation is included, and API errors do not expose credential values.
2. Run the Python test suite and confirm the new Arr auth test fails because no auth reconciliation exists.
3. Add a helper that reads the two runtime secret files and updates only the Arr host authentication fields through the API key already extracted from `config.xml`. Preserve other host settings and never include request/response values in error messages.
4. Add a Bazarr test proving its API settings reconciliation applies the username and the app's expected hash of the password without logging or storing the plain value. Test repeat runs remain stable.
5. Run the tests and observe the Bazarr test fail before adding the minimal adapter logic. Update only the declared auth settings; retain all unmanaged Bazarr settings.
6. Run `python3 tests/test_media_app_reconciliation.py modules/nixos/scripts` and require all tests to pass.

### Task 3: Apply Mylar3 login in its protected runtime config

**Files:**
- Modify: `tests/test_media_app_reconciliation.py`
- Modify: `modules/nixos/media-management.nix`
- Modify: `modules/nixos/scripts/mylar3_config.py`
- Modify: `modules/nixos/mylar3.nix` only if service secret access/ordering is not expressible from the media module

**Steps:**
1. Add a test that overlays `Interface.HTTP_USERNAME` and `Interface.HTTP_PASSWORD` from runtime files while preserving unrelated imported INI settings and ensuring the output file remains restricted.
2. Run the focused Python tests and confirm failure because these fields are not declared.
3. Add the two secret-backed settings and make Mylar3 wait for Opnix before rendering/starting. Preserve its existing Forms-auth setting and `0600` config file behavior.
4. Rerun the focused Python tests and confirm they pass.

### Task 4: Verify Jellyfin's declared admin account at runtime

**Files:**
- Create: `modules/nixos/scripts/jellyfin_admin_auth.py`
- Modify: `tests/test_media_app_reconciliation.py`
- Modify: `modules/nixos/media-management.nix` or `modules/nixos/media-config.nix`

**Steps:**
1. Add fake-server tests for successful username/password authentication plus administrator verification, rejection of non-admin accounts, missing/empty secret files, and safe errors that do not contain credential values.
2. Run the focused Python tests and confirm the verifier is missing.
3. Implement a small stdlib HTTP verifier using Jellyfin's username authentication endpoint and authenticated current-user endpoint. Do not change Jellyfin's user database or disable authentication.
4. Add a restricted post-start oneshot that waits for Jellyfin and Opnix and runs as the Jellyfin account with access only to its two secret files.
5. Rerun the Python tests and confirm they pass.

### Task 5: Validate and review the complete change

**Steps:**
1. Run the Python reconciliation tests.
2. Run `devenv tasks run check:lint`.
3. Run the focused Nix media-management and media-app-reconciliation checks with the working tree visible; fix any failures before proceeding.
4. Inspect the diff for secret values, unnecessary `op://` vault prefixes, broad secret permissions, auth weakening, or changes to Transmission/staging behavior.
5. Commit the completed changes with a conventional `feat:` message using Jujutsu, then run final Nix checks without `--impure` as required by the repository.

## Interfaces

- Arr reconciler config receives only secret file paths. Existing API keys continue to come from each Arr's runtime `config.xml`.
- Bazarr auth is applied by its existing API adapter; its password is hashed using Bazarr's expected representation before comparing current state, while the API receives the plaintext only in memory over loopback.
- Mylar3 uses the existing `{ secret = path; }` INI renderer contract.
- Jellyfin accepts the current credentials and proves the resulting account has administrator rights; a failed check does not mutate account state.

## Review Focus

- Confirm no secret value is captured by `pkgs.writeText`, emitted into systemd environment/unit text, or used as a process argument.
- Confirm all secret files have restrictive ownership/modes and no app gains access to another app's credentials unnecessarily.
- Confirm Arr auth remains `Forms`/`Enabled`, the API reconcilers do not replace unrelated host configuration, and Bazarr password reconciliation is idempotent.
- Confirm Jellyfin verification only authenticates and checks admin policy; it must not reset users, alter the database, or expose credentials in output.
- Confirm no Transmission, Prowlarr, seedbox staging, media paths, or deletion behavior changed.
