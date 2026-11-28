# Faster PR Check Shards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce work per PR validation runner by planning two checks per non-VM shard.

**Architecture:** Keep existing check selection and matrix planning, but set non-VM PR batches to two while preserving the six-runner cap and 25-minute timeout. Make `system:switch` consume a validated, immutable `git+file` flake reference pinned to the selected workspace commit for all configuration lookups and rebuilds, while retaining current-directory behavior outside a workspace.

**Tech Stack:** GitHub Actions YAML, Bash regression tests, Jujutsu, GitHub CLI.

**Spec:** `docs/superpowers/specs/2026-11-20-pr-check-shards-design.md`

## Global Constraints

- Non-VM PR check batch size is two.
- Preserve `max-parallel: 6` and `timeout-minutes: 25`.
- Do not change check selection or the independent VM check job.
- Use the same commit-pinned flake reference for every `system:switch` evaluation and rebuild; reject an invalid or empty explicit workspace root.
- Obtain the pinned revision with `jj --ignore-working-copy ... log -r @ -T commit_id`; do not use a mutable path reference.
- Do not run the actual system switch during implementation or testing.
- Rebase on the latest remote `main`; push only the new bookmark `fix/workspace-switch-and-pr-check-shards` because PR 564 has merged.

## Review Focus

- **Planner batch size:** The workflow regression test must require exactly two checks per planned batch.
- **Concurrency:** Preserve the six-runner cap; verify its existing workflow assertion remains unchanged.
- **Timeout:** Preserve the 25-minute timeout; verify its existing workflow assertion remains unchanged.
- **VM isolation:** Leave the VM check job and its trigger untouched.
- **Selection behavior:** Leave changed-path selection untouched; run its existing regression test.
- **Workspace target:** With `JJ_WORKSPACE_ROOT` set to a valid workspace, Darwin and NixOS config discovery, secret lookup, and rebuild commands must use the same `git+file` reference pinned to its `jj` commit; without the variable, preserve the current-directory fallback.
- **Invalid workspace:** If `JJ_WORKSPACE_ROOT` is set to empty or does not contain `flake.nix`, fail before any switch command instead of silently applying the main checkout.
- **Dirty-tree isolation:** Pass `?rev=<commit>` to all Nix commands so `allow-dirty = true` cannot include later working-tree edits or change the source between lookup and rebuild.

---

## File Structure

- `tests/test-ci-workflows.sh`: asserts the PR workflow requests two-check shards while preserving concurrency and timeout expectations.
- `.github/workflows/pr-validation.yml`: sets the non-VM PR check planner's batch size to two and updates the explanatory comment.
- `modules/common/scripts/jj-workspace-lib`: resolves the workspace's immutable Git flake reference and validates explicit workspace paths.
- `devenv.nix`: exports workspace context and uses the resolved flake reference for every `system:switch` evaluation and rebuild.
- `.envrc`: retains the workspace-aware wrapper and explains which committed workspace tree is switched.
- `tests/test-workspace-switch.sh` and `tests/test-switch-task.nix`: cover workspace-root resolution and task command wiring.

## Task 1: Split non-VM PR validation checks into two-check shards

**Files:**
- Modify: `tests/test-ci-workflows.sh`
- Modify: `.github/workflows/pr-validation.yml`

**Interfaces:**
- Consumes: existing `ci-checks.sh plan non-vm` matrix planner.
- Produces: matrix entries of up to two checks, with existing concurrency, timeout, and selection behavior preserved.

- [ ] **Step 1: Update the workflow regression expectation first.** Change the exact planner assertion in `tests/test-ci-workflows.sh` from `{batchSize:4,checkPrefixes:$prefixes}` to `{batchSize:2,checkPrefixes:$prefixes}`.
- [ ] **Step 2: Verify RED.** Run `bash tests/test-ci-workflows.sh`; it must fail because `pr-validation.yml` still requests four checks.
- [ ] **Step 3: Update the workflow.** Set the planner input to `batchSize:2` and revise the shard comment to say each runner builds up to two checks. Keep `max-parallel: 6` and `timeout-minutes: 25` unchanged.
- [ ] **Step 4: Verify GREEN.** Run `bash tests/test-ci-workflows.sh`, `bash tests/test-ci-check-groups.sh`, `bash tests/test-ci-change-selection.sh`, and `bash tests/test-ci-pr-validation-selection.sh`.
- [ ] **Step 5: Run repository checks.** Run `devenv tasks run check:lint` and `devenv tasks run test:build-checks`.
- [ ] **Step 6: Commit the implementation.** Use `jj describe -m "ci: split PR validation checks into smaller shards"`.

## Task 2: Make system switching use the current workspace flake

**Files:**
- Modify: `modules/common/scripts/jj-workspace-lib`
- Modify: `devenv.nix`
- Modify: `tests/test-workspace-switch.sh`
- Modify: `tests/test-switch-task.nix`
- Modify: `.envrc`

**Interfaces:**
- Produces: `resolve_jj_flake_ref()`, which prints `git+file://<repo-root>?rev=<jj commit id>`, falls back to the current directory when `JJ_WORKSPACE_ROOT` is unset, and fails when an explicit root is empty or invalid.
- Consumes: the workspace root exported by `.envrc` or the Devenv shell hook.

- [ ] **Step 1: Write failing shell tests** for pinned workspace-root selection, unset-variable fallback, empty and invalid explicit roots, and the `jj --ignore-working-copy` revision arguments.
- [ ] **Step 2: Extend `tests/test-switch-task.nix` before implementation** to assert the pinned resolver is used for configuration discovery, secret lookup, and both platform rebuild commands.
- [ ] **Step 3: Verify RED.** Run `bash tests/test-workspace-switch.sh`; expect failures for the missing resolver and empty-root guard. In a clean path copy, build `checks.<current-system>.switch-task`; expect failure because the task does not yet use a pinned `FLAKE_REF`.
- [ ] **Step 4: Implement `resolve_jj_flake_ref()`** in `modules/common/scripts/jj-workspace-lib`, source it in `system:switch`, validate roots, obtain the commit ID with `jj --ignore-working-copy --repository <workspace> log -r @ -T commit_id`, and emit one immutable `git+file` reference.
- [ ] **Step 5: Route every switch lookup and rebuild through `FLAKE_REF`** for Darwin and NixOS. Preserve an inherited `JJ_WORKSPACE_ROOT` from the Devenv shell hook, including explicit empty values, and keep its short switch functions bound to the exported repo-root variable.
- [ ] **Step 6: Update workspace guidance** in `.envrc` to state that the switch evaluates the current workspace commit.
- [ ] **Step 7: Verify GREEN** with `bash tests/test-workspace-switch.sh` and the four CI-helper suites from Task 1.
- [ ] **Step 8: Commit** with `jj describe -m "fix: pin system switch to workspace revision"` before running Nix validation.
- [ ] **Step 9: Run repository checks** with `devenv tasks run check:lint`, `devenv tasks run test:build-checks`, and the focused `switch-task` check from a clean path copy; do not invoke `system:switch`.

## Task 3: Rebase the follow-up and publish a new branch

**Files:**
- No additional files.

- [ ] **Step 1: Fetch current remote bookmarks** with `jj git fetch` and verify the remote `main` target.
- [ ] **Step 2: Rebase the follow-up commits** onto fetched remote `main` with Jujutsu; preserve all source changes when resolving conflicts.
- [ ] **Step 3: Set `fix/workspace-switch-and-pr-check-shards`** to the rebased head and verify the diff contains the shard and workspace-switch changes without duplicating the already-merged `.envrc` change.
- [ ] **Step 4: Push only `fix/workspace-switch-and-pr-check-shards`** with `jj git push --bookmark fix/workspace-switch-and-pr-check-shards`.
- [ ] **Step 5: Verify the remote bookmark** matches the local head and report that it is ready for a new PR.
