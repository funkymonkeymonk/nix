# GC Sudo Password Reference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make system tasks retrieve the configured sudo reference from Jujutsu workspaces instead of silently falling back when Nix cannot parse their Git metadata.

**Architecture:** Extract shared shell helpers in `devenv.nix` for resolving the current configuration and its sudo-password path. Use `path:.` for Nix evaluation to avoid Git worktree metadata parsing. Reuse the helpers from both `system:switch` and `system:gc`, removing duplicated lookup logic while keeping Darwin primary-user matching consistent.

**Tech Stack:** Nix task definitions, Bash, existing Nix `runCommand` checks.

**Spec:** Approved in conversation: use the same machine-config resolution for GC and system switch, and reduce duplicated host/reference lookup code.

## Global Constraints

- Preserve fully qualified `op://` sudo references.
- Resolve unqualified references through the selected machine's `defaultVault`.
- Preserve Darwin exact-hostname matching followed by `system.primaryUser` matching.
- Never fetch or print the sudo secret in tests.

## Review Focus

- Jujutsu worktree metadata is unsupported by the Nix Git fetcher: task lookups use `path:.` and do not silently fall back due to Git metadata.
- Darwin short hostname differs from the flake configuration name: GC resolves via the primary-user fallback.
- Fully qualified references pass through unchanged.
- Missing custom references retain the default-vault/hostname fallback.

---

### Task 1: Share machine and sudo-reference resolution

**Files:**
- Modify: `tests/test-switch-task.nix`
- Modify: `devenv.nix`

**Interfaces:**
- `resolve_machine_config_name(config_set, hostname)` returns the matching Darwin configuration name, or the hostname for NixOS.
- `get_sudo_password_path(config_set, config_name, hostname)` returns the configured or fallback 1Password URI.

- [x] **Step 1: Add regression assertions**

Assert both tasks call the shared config and sudo-path helpers, that switch computes one sudo path before its platform branch, and that the shared Darwin resolver checks `system.primaryUser` if no exact hostname match exists.

- [x] **Step 2: Verify the test fails**

The `switch-task` check failed first for missing shared helpers, then for the missing `path:.` lookup required to avoid jj Git metadata.

- [x] **Step 3: Implement shared helpers**

Define the helpers once in the shared shell fragment. Use them from `system:switch` and `system:gc`, preserving NixOS hostname selection and existing reference fallback semantics.

- [x] **Step 4: Verify**

The focused `switch-task` check and `devenv tasks run check:lint` pass. `devenv tasks run test:build-checks` is blocked because its `test:eval` dependency invokes the Git flake fetcher, which rejects `extensions.relativeworktrees`; `nix flake check path:.` was also attempted but cannot build the repository's Linux-targeted check without the unavailable MegamanX builder.
