# Faster PR Check Shards Design

## Intent

Reduce the longest PR validation shard runtime so Nix checks are less likely to hit the existing job timeout.

## Current state

- The PR workflow plans four checks per shard, allows six shard runners at once, and gives each runner 25 minutes.
- Two four-check shards reached the 25-minute limit while building Nix dependencies.
- VM check scheduling is independent and should remain unchanged.

## Approaches considered

1. **Two checks per shard. Selected.** Halve the planned work per runner while retaining the six-runner concurrency cap and the 25-minute budget. This limits the increase in runner setup overhead compared with one-check shards.
2. **One check per shard.** More granular and isolates expensive checks, but doubles the shard count again and adds substantially more runner setup and cache traffic.
3. **Manually weighted check groups or a longer timeout.** Weighted groups need reliable per-check timing data and more planner complexity; a longer timeout does not make jobs faster.

## Goals and constraints

- Plan non-VM PR check shards with a batch size of two.
- Keep `max-parallel: 6`, `timeout-minutes: 25`, check selection, and independent VM scheduling unchanged.
- Update workflow regression coverage to pin the two-check batch size.
- Rebase the PR branch onto the latest `main` and push the updated branch.

## Non-goals

- Change which checks are selected for a PR.
- Change Nix build parallelism, VM checks, or the per-job timeout.
- Add a duration-weighted planner or new runtime telemetry.
