# Faster PR Check Shards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce work per PR validation runner by planning two checks per non-VM shard.

**Architecture:** Keep the existing check-selection and matrix-building logic. Change the PR workflow's `batchSize` from four to two, preserve its six-runner cap and 25-minute timeout, and update the workflow regression assertion.

**Tech Stack:** GitHub Actions YAML, Bash regression tests, Jujutsu, GitHub CLI.

**Spec:** `docs/superpowers/specs/2026-11-20-pr-check-shards-design.md`

## Global Constraints

- Non-VM PR check batch size is two.
- Preserve `max-parallel: 6` and `timeout-minutes: 25`.
- Do not change check selection or the independent VM check job.
- Rebase on the latest remote `main`; push only the PR bookmark `docs/fix-envrc-stale-tip`.

## Review Focus

- **Planner batch size:** The workflow regression test must require exactly two checks per planned batch.
- **Concurrency:** Preserve the six-runner cap; verify its existing workflow assertion remains unchanged.
- **Timeout:** Preserve the 25-minute timeout; verify its existing workflow assertion remains unchanged.
- **VM isolation:** Leave the VM check job and its trigger untouched.
- **Selection behavior:** Leave changed-path selection untouched; run its existing regression test.

---

## File Structure

- `tests/test-ci-workflows.sh`: asserts the PR workflow requests two-check shards while preserving concurrency and timeout expectations.
- `.github/workflows/pr-validation.yml`: sets the non-VM PR check planner's batch size to two and updates the explanatory comment.

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

## Task 2: Rebase and publish the PR branch

**Files:**
- No additional files.

- [ ] **Step 1: Fetch current remote bookmarks** with `jj git fetch` and verify the remote `main` target.
- [ ] **Step 2: Rebase the PR branch** onto the fetched remote `main` with Jujutsu; resolve no conflicts by discarding work.
- [ ] **Step 3: Point `docs/fix-envrc-stale-tip` at the rebased PR head** and verify the branch contains the `.envrc` change and shard change.
- [ ] **Step 4: Push only `docs/fix-envrc-stale-tip`** with `jj git push --bookmark docs/fix-envrc-stale-tip`.
- [ ] **Step 5: Verify the remote PR head** matches the pushed bookmark and note the newly triggered CI run.
