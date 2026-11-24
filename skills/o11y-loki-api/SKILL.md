---
name: o11y-loki-api
description: Use when investigating this repository's journald logs, Vector labels, Loki LogQL queries, or Grafana log panels through API access.
---

# Loki API Workflow

Loki runs privately on `drlight`. Query it through Grafana's datasource API;
do not SSH to inspect logs unless the API cannot provide the needed evidence.

## Labels

Vector attaches labels including:

```text
host
service
service_name
severity
```

The Ultra worker stream is:

```logql
{host="drlight",service="ultra-media-download-stage-start"}
```

## Nested Worker JSON

The journald record is JSON, but the worker's JSON event is nested in its
`message` field. This is the required pipeline shape:

```logql
{host="drlight",service="ultra-media-download-stage-start"}
| json
| line_format "{{.message}}"
| json
| event="staging_progress"
```

Do not use `| json | event="staging_progress"` alone; it returns no rows because
`event` is inside `message`.

## Query Through Grafana

Discover the Loki UID and send a LogQL query through `/api/ds/query`:

```bash
LOKI_UID=$(curl -fsS -u "$GRAFANA_USER:$GRAFANA_TOKEN" \
  "$GRAFANA_URL/api/datasources/name/Loki" | jq -r .uid)
jq -n --arg uid "$LOKI_UID" '{
  queries: [{
    refId: "A",
    datasource: {type: "loki", uid: $uid},
    expr: "{host=\"drlight\",service=\"ultra-media-download-stage-start\"} | json | line_format \"{{.message}}\" | json | event=\"staging_progress\"",
    queryType: "range",
    maxLines: 1000,
    intervalMs: 60000,
    maxDataPoints: 1000
  }],
  from: "now-3h",
  to: "now"
}' > /tmp/loki-query.json
curl -fsS -u "$GRAFANA_USER:$GRAFANA_TOKEN" \
  -H 'Content-Type: application/json' -X POST \
  "$GRAFANA_URL/api/ds/query" -d @/tmp/loki-query.json | jq .
```

Inspect `results.A.frames` and the returned rows, not only the HTTP status.

## Common Event Queries

```logql
# Aggregate transfer progress
{host="drlight",service="ultra-media-download-stage-start"}
| json | line_format "{{.message}}" | json | event="staging_progress"

# End-of-run summary
{host="drlight",service="ultra-media-download-stage-start"}
| json | line_format "{{.message}}" | json | event="sync_run_summary"

# Systemd lifecycle events
{host="drlight",service="systemd"}
| json | UNIT="ultra-media-download-stage.service"
```

## References

- [Loki HTTP API](https://grafana.com/docs/loki/latest/reference/loki-http-api/)
- [LogQL](https://grafana.com/docs/loki/latest/query/)
