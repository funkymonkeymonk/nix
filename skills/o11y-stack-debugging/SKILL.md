---
name: o11y-stack-debugging
description: Use when an observability dashboard panel is blank, stale, or contradictory in this repository's Grafana, Prometheus, or Loki stack.
---

# API-First Observability Debugging

Trace the data path in this order:

```text
Grafana panel definition
  -> Grafana datasource UID
  -> Grafana /api/ds/query response
  -> Prometheus or Loki result frames
  -> exporter/scrape or Vector/log stream
```

## Required Workflow

1. Fetch the live dashboard with `/api/dashboards/uid/<uid>`.
2. Copy the exact target expression and datasource UID from the live panel.
3. Run that target through `/api/ds/query` with a narrow time range.
4. Inspect result frames, row counts, labels, and errors.
5. Compare the live definition to the declarative Nix source.
6. Fix the declarative source, run dashboard tests, deploy through Machines,
   and re-query the API.

## Interpretation

| Observation | Likely boundary |
|---|---|
| Panel target absent from live dashboard | Grafana provisioning/deployment |
| `/api/ds/query` returns an error | Datasource or query syntax |
| Query succeeds with zero frames | Labels, time range, or pipeline parsing |
| Prometheus works but Loki is empty | Vector labels or nested JSON parsing |
| Datasource query has rows but panel is blank | Grafana transformations/field configuration |
| Live dashboard differs from Nix source | Provisioning or deployment drift |

## Access Policy

- Use Grafana's authenticated HTTP API for dashboard and datasource access.
- Use Grafana's datasource proxy for Prometheus and Loki.
- Never put passwords, API tokens, or secret values in commands, files, logs,
  or dashboard labels.
- SSH is a last resort only when the required API evidence is unavailable;
  record the reason and use read-only inspection.

## Repository References

- Dashboard source: `modules/nixos/grafana.nix`
- Prometheus source: `modules/nixos/prometheus.nix`
- Loki source: `modules/nixos/loki.nix`
- Vector source: `modules/nixos/vector.nix`
- Ultra sync source: `modules/nixos/scripts/ultra-media-sync.py`
- Metrics source: `modules/nixos/scripts/ultra-media-download-stage.py`
