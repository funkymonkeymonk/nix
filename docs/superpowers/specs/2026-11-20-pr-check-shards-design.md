# Faster PR Check Shards Design

## Intent

Reduce the longest PR validation shard runtime so Nix checks are less likely to hit the existing job timeout.

## Current state

- The PR workflow plans four checks per shard, allows six shard runners at once, and gives each runner 25 minutes.
- Two four-check shards reached the 25-minute limit while building Nix dependencies.
- VM check scheduling is independent and should remain unchanged.
- The workspace-aware `switch` wrapper runs the task from the main checkout, but `system:switch` evaluates and rebuilds relative `./#...` flake references there. It does not currently use the invoking workspace's commit, despite the documented promise.

## Approaches considered

1. **Two checks per shard. Selected.** Halve the planned work per runner while retaining the six-runner concurrency cap and the 25-minute budget. This limits the increase in runner setup overhead compared with one-check shards.
2. **One check per shard.** More granular and isolates expensive checks, but doubles the shard count again and adds substantially more runner setup and cache traffic.
3. **Manually weighted check groups or a longer timeout.** Weighted groups need reliable per-check timing data and more planner complexity; a longer timeout does not make jobs faster.

For workspace switching, three approaches were considered:

1. **Pass an immutable workspace flake reference through the existing task. Selected.** Continue launching `system:switch` from the main repo root, resolve the workspace's Jujutsu commit ID once, and use a `git+file` flake reference pinned with `?rev=<commit>` for every lookup and rebuild. This preserves task setup while making the documented workspace behavior real and preventing dirty-tree drift.
2. **Run the task directly from the workspace.** Simpler at the wrapper, but leaves task-level root assumptions implicit and depends on workspace flake discovery.
3. **Create a temporary snapshot of the workspace commit.** Strong isolation from uncommitted files, but adds per-switch snapshot and cleanup machinery.

## Goals and constraints

- Plan non-VM PR check shards with a batch size of two.
- Keep `max-parallel: 6`, `timeout-minutes: 25`, check selection, and independent VM scheduling unchanged.
- Update workflow regression coverage to pin the two-check batch size.
- Make `system:switch` use an immutable flake reference for the current workspace commit across all Nix evaluations and rebuilds; retain current-directory behavior for ordinary invocations.
- Pin the Git-backed flake reference to the commit returned by `jj log`; never use a mutable path reference that can include dirty changes or change between lookup and rebuild.
- Fail clearly if an explicitly supplied workspace root is invalid rather than silently switching the main checkout.
- Treat an explicitly empty `JJ_WORKSPACE_ROOT` as invalid, not as an unset variable.
- Rebase the follow-up changes onto the latest `main` and publish them on a new branch because PR 564 has already merged.

## Non-goals

- Change which checks are selected for a PR.
- Change Nix build parallelism, VM checks, or the per-job timeout.
- Add a duration-weighted planner or new runtime telemetry.
- Run `system:switch` or apply a host configuration during development or testing.
