# Seedbox Quota Guard Runtime Loader Recovery Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix the Drlight quota guard's packaged runtime-helper lookup so its timer can start successfully, then deploy the guard.

**Architecture:** Keep the existing guard behavior and isolated Nix store entrypoint. Update its runtime loader to prefer a helper beside the entrypoint, then search absolute directories from `sys.path` (including the configured Nix script bundle). Missing helpers remain fail-closed. Validate the packaged layout with a regression test, then use a fresh one-machine Machines plan for deployment.

**Tech Stack:** Python standard library, `unittest`, NixOS systemd, Devenv Machines.

**Spec:** `docs/superpowers/specs/2026-11-26-seedbox-quota-guard-design.md`

## Global Constraints

- Pause at 3.8 TB decimal; resume below 3.5 TB decimal; poll live quota every minute.
- Stop only incomplete torrents in downloading or queued-to-download states; leave completed torrents seeding.
- Resume only torrent hashes recorded as paused by this guard; do not delete payloads.
- If usage or RPC state is unavailable, never resume from stale or unknown usage.
- Missing runtime dependencies remain fail-closed.
- Deploy only through a reviewed Machines plan for exactly `drlight`; do not use direct `nixos-rebuild`.

## Review Focus

- The guard entrypoint is a separate store path while helpers are in the shared `PYTHONPATH` bundle; test that this packaged layout resolves the helper.
- A same-directory helper must retain precedence over a `sys.path` helper; test the selection order.
- A missing helper must still raise the safe runtime-dependency error; test the fail-closed case.
- Relative and empty `sys.path` entries must not become helper search roots; test that only absolute directories are considered.
- The deployment must not resume manually paused torrents or completed seeds; verify the guard starts with an empty/valid state and reports `status=ok` at the current below-threshold quota.

---

### Task 1: Resolve runtime helpers from the packaged script bundle

**Files:**
- Modify: `modules/nixos/scripts/ultra_media_space_guard.py`
- Test: `tests/test-ultra-media-space-guard.py`
- Modify: `docs/superpowers/specs/2026-11-26-seedbox-quota-guard-design.md`

**Interfaces:**
- Preserve `_load_runtime_module(name: str, filename: str) -> Any` and its module caching. Resolve `filename` beside the guard entrypoint first, then from absolute directories in `sys.path`; retain the existing error when no file is found or loading fails.

- [x] Add tests for helper lookup from a separate `PYTHONPATH` directory, same-directory precedence, ignored relative/empty search entries, and missing-helper failure.
- [x] Run `PYTHONPATH=modules/nixos/scripts python tests/test-ultra-media-space-guard.py` and confirm the packaged-layout case fails before the fix.
- [x] Implement the narrow helper-path fallback without changing guard pause/resume policy.
- [x] Run the focused guard suite and the cleanup/RPC Python tests; confirm all pass.
- [x] Commit the tested fix with `jj describe`.

### Task 2: Validate and deploy the repaired guard

**Files:**
- No additional source files.

- [x] Commit the design and plan documentation changes before Nix validation.
- [x] Run `devenv tasks run check:lint`, `devenv tasks run test:build-checks`, `devenv tasks run test:eval`, and `devenv tasks run test:all`.
- [x] Create a fresh plan with `devenv tasks run machines:plan --input machine=drlight`; verify it targets only Drlight and review the complete plan plus closure diff.
- [x] Apply only that reviewed plan with its exact plan ID.
- [x] Run `devenv tasks run machines:check --input machine=drlight`; verify the guard timer is active and the service reports `status=ok` without resuming torrents outside guard-owned state.
- [x] Confirm the current generation is the requested one and record the initial live usage and guard metrics for the one-week review.
