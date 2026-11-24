# Grafana API Feedback Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Document and enable a fast Grafana API development loop without repeated SecretSpec reason prompts.

**Architecture:** Keep Nix as the durable dashboard source. Use a separate non-provisioned Grafana dashboard copy for API experiments, with credentials injected by `op run`.

**Tech Stack:** Grafana HTTP API, Loki/Prometheus datasource API, 1Password CLI, SecretSpec, Markdown.

**Spec:** `docs/superpowers/specs/2026-11-21-grafana-api-feedback-loop-design.md`

## Global Constraints

- Do not write resolved credentials to files, logs, or dashboard definitions.
- Do not treat API development copies as durable production configuration.
- Do not edit provisioned dashboards through the Grafana API.

## Review Focus

- The skill must state that Grafana rejects writes to provisioned dashboards.
- The workflow must inspect API query frames and errors, not only HTTP status.
- Prometheus table targets must use instant queries when the panel needs current rows.
- 1Password references must remain unresolved in the environment file.

### Task 1: Grafana API workflow documentation

**Files:**
- Modify: `skills/o11y-grafana-api/SKILL.md`

- [ ] Add the `op run --env-file` credential pattern.
- [ ] Have the skill document the live dashboard inspection and `/api/ds/query` evidence loop.
- [ ] Have the skill document creation and update of a non-provisioned development dashboard copy.
- [ ] Have the skill document instant Prometheus queries for current table panels.
- [ ] Have the skill document the distinction between API experiments and Nix production changes.
- [ ] Run the Markdown style review.

### Task 2: SecretSpec reason policy

**Files:**
- Modify: `secretspec.toml`

- [ ] Set the project `require_reason` policy to `false`.
- [ ] Run the existing SecretSpec and configuration checks.

### Task 3: Verification

- [ ] Run `devenv tasks run check:lint`.
- [ ] Run `devenv tasks run test:build-checks`.
- [ ] Describe the jj change and leave an empty working commit.
