# Faster PR Check Shards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce work per PR validation runner by planning two checks per non-VM shard.

**Architecture:** Keep existing check selection and matrix planning, but set non-VM PR batches to two while preserving the six-runner cap and 25-minute timeout. Make `system:switch` consume a validated workspace flake root for all configuration lookups and rebuilds, while retaining current-directory behavior outside a workspace.

**Tech Stack:** GitHub Actions YAML, Bash regression tests, Jujutsu, GitHub CLI.

**Spec:** `docs/superpowers/specs/2026-11-20-pr-check-shards-design.md`

## Global Constraints

- Non-VM PR check batch size is two.
- Preserve `max-parallel: 6` and `timeout-minutes: 25`.
- Do not change check selection or the independent VM check job.
- Use the same resolved flake root for every `system:switch` evaluation and rebuild; reject an invalid explicit workspace root.
- Preserve Git-backed flake semantics so the selected source is the committed workspace revision.
- Do not run the actual system switch during implementation or testing.
- Rebase on the latest remote `main`; push only the PR bookmark `docs/fix-envrc-stale-tip`.

## Review Focus

- **Planner batch size:** The workflow regression test must require exactly two checks per planned batch.
- **Concurrency:** Preserve the six-runner cap; verify its existing workflow assertion remains unchanged.
- **Timeout:** Preserve the 25-minute timeout; verify its existing workflow assertion remains unchanged.
- **VM isolation:** Leave the VM check job and its trigger untouched.
- **Selection behavior:** Leave changed-path selection untouched; run its existing regression test.
- **Workspace target:** With `JJ_WORKSPACE_ROOT` set to a valid workspace, Darwin and NixOS config discovery, secret lookup, and rebuild commands must all target it; without the variable, preserve the current-directory fallback.
- **Invalid workspace:** If `JJ_WORKSPACE_ROOT` is set but does not contain `flake.nix`, fail before any switch command instead of silently applying the main checkout.

---

## File Structure

- `tests/test-ci-workflows.sh`: asserts the PR workflow requests two-check shards while preserving concurrency and timeout expectations.
- `.github/workflows/pr-validation.yml`: sets the non-VM PR check planner's batch size to two and updates the explanatory comment.
- `modules/common/scripts/jj-workspace-lib`: resolves the workspace flake root and validates explicit workspace paths.
- `devenv.nix`: exports workspace context and uses the resolved flake root for every `system:switch` evaluation and rebuild.
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
- Produces: `resolve_jj_flake_root()`, which prints `JJ_WORKSPACE_ROOT` when it names a directory containing `flake.nix`, falls back to the current directory when unset, and fails when an explicit workspace root is invalid.
- Consumes: the workspace root exported by `.envrc` or the Devenv shell hook.

- [ ] **Step 1: Write failing shell tests** for workspace-root selection, unset-variable fallback, and an invalid explicit root.
- [ ] **Step 2: Verify RED** by running `bash tests/test-workspace-switch.sh` and confirming only the new resolution cases fail.
- [ ] **Step 3: Implement the resolver** in `modules/common/scripts/jj-workspace-lib`, source it in `system:switch`, and assign its output to one `FLAKE_ROOT` variable.
- [ ] **Step 4: Route every switch lookup and rebuild through `FLAKE_ROOT`** for Darwin and NixOS. Export the workspace/repo roots from the Devenv shell hook and keep its short switch functions bound to the exported repo-root variable.
- [ ] **Step 5: Update workspace guidance** in `.envrc` to state that the switch evaluates the current workspace commit.
- [ ] **Step 6: Extend `tests/test-switch-task.nix`** to assert the shared root resolver is used for configuration discovery, secret lookup, and both platform rebuild commands.
- [ ] **Step 7: Verify GREEN** with `bash tests/test-workspace-switch.sh`, `nix build "path:$PWD#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw).switch-task" --no-link` from a clean path copy, and the four CI-helper suites from Task 1.
- [ ] **Step 8: Run repository checks** with `devenv tasks run check:lint` and `devenv tasks run test:build-checks`; do not invoke `system:switch`.
- [ ] **Step 9: Commit** with `jj describe -m "fix: switch from the current jj workspace"`.

## Task 3: Rebase and publish the PR branch

**Files:**
- No additional files.

- [ ] **Step 1: Fetch current remote bookmarks** with `jj git fetch` and verify the remote `main` target.
- [ ] **Step 2: Rebase the PR branch** onto the fetched remote `main` with Jujutsu; resolve no conflicts by discarding work.
- [ ] **Step 3: Point `docs/fix-envrc-stale-tip` at the rebased PR head** and verify the branch contains the `.envrc`, shard, and workspace-switch fixes.
- [ ] **Step 4: Push only `docs/fix-envrc-stale-tip`** with `jj git push --bookmark docs/fix-envrc-stale-tip`.
- [ ] **Step 5: Verify the remote PR head** matches the pushed bookmark and note the newly triggered CI run.
