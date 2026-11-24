# Repository Grafana Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor the Grafana skills relevant to this repository into devenv’s project-local agent skill directory without changing global Home Manager skills.

**Architecture:** Add `grafana/skills` as a pinned raw devenv input. Build a small Nix store tree containing all `grafana-core` skills plus the repository-used Loki, Prometheus, and datasource-provisioning skills, then materialize that tree under `.agents/skills/` through devenv. Existing `personal-skills` and global installation remain unchanged.

**Tech Stack:** devenv inputs/lockfile, Nix derivations, project-local Agent Skills directory.

**Spec:** User request and devenv issue #2441.

## Global Constraints

- Do not add Grafana skills to `flake.nix`, `myConfig.skills`, Home Manager, or global skill installation.
- Pin the upstream source through `devenv.yaml`/`devenv.lock`.
- Vendor only all `grafana-core` skills and the in-use `grafana-lgtm/loki`, `grafana-lgtm/prometheus`, and `grafana-datasources/datasources-provisioning` skills.
- Materialize skills under the repository-local `.agents/skills/` path.

## Review Focus

- The devenv input must be reproducibly locked and not silently use the flake’s global inputs.
- Entering devenv must expose complete skill directories, including supporting files, not only `SKILL.md`.
- Unrelated Grafana Cloud, plugin, App SDK, and k6 skills must not be installed.
- Existing personal/global skill installation must remain unchanged.
- Skill names and paths must remain compatible with Agent Skills discovery.

### Task 1: Pin and vendor Grafana skills through devenv

**Files:**
- Modify: `devenv.yaml`
- Modify: `devenv.lock`
- Modify: `devenv.nix`
- Test: `tests/test-devenv-grafana-skills.nix`
- Modify: `tests/default.nix`

- [ ] Add a failing test asserting the selected local skill paths, complete `SKILL.md` files, and absence of unrelated plugin groups.
- [ ] Add the raw `grafana-skills` devenv input and update `devenv.lock`.
- [ ] Define a Nix vendor tree from the pinned input and materialize it through devenv under `.agents/skills/`.
- [ ] Add a devenv-focused check that confirms selected skills are available and personal skill configuration is unaffected.
- [ ] Run the focused test and lint.
- [ ] Commit with `feat: vendor repository Grafana skills through devenv`.

### Task 2: Full verification

- [ ] Run `devenv tasks run check:lint`.
- [ ] Run `devenv tasks run test:eval`.
- [ ] Run the focused devenv skill test.
- [ ] Confirm `jj status` is clean and leave an empty jj working-copy commit.
