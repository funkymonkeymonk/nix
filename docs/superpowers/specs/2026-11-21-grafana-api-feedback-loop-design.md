# Grafana API Feedback Loop Design

## Intent

Document a fast Grafana dashboard workflow that uses the Grafana HTTP API for
development feedback, while keeping declarative Nix dashboard definitions as
the durable source.

## Goals

- Fetch live dashboards and datasource UIDs through Grafana's API.
- Create or update a separate, non-provisioned API development copy.
- Query Loki and Prometheus through `/api/ds/query`.
- Inspect frames, rows, labels, and errors before changing a query.
- Use `op run --env-file` with 1Password references instead of copying secrets.
- Disable the repository-wide SecretSpec reason requirement as requested.

## Non-goals

- Make API edits to provisioned production dashboards.
- Store resolved credentials in the repository or temporary files.
- Replace declarative Nix dashboard changes for permanent configuration.

## Approach

The Grafana skill will describe an API-first development loop with a distinct
development dashboard UID. The repository SecretSpec project will disable the
reason gate so repeated API commands do not require a reason. 1Password still
resolves the referenced credentials at process start.

## Constraints

- Never print or persist resolved passwords or tokens.
- Use the existing Grafana URL and dashboard UID conventions.
- Keep production dashboard deployment separate from API experimentation.
