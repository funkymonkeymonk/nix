---
name: o11y-prometheus-api
description: Use when investigating this repository's Prometheus metrics, scrape state, query results, alerts, or Ultra media sync telemetry through Grafana's API.
---

# Prometheus API Workflow

Prometheus runs privately on `drlight`; access it through Grafana's datasource
query API, not SSH and not direct port 9090 access.

## Repository Metrics

The Ultra sync exporter publishes:

```text
ultra_media_sync_active
ultra_media_sync_status
ultra_media_sync_torrents_total
ultra_media_sync_torrents_published
ultra_media_sync_bytes_total
ultra_media_sync_bytes_transferred
ultra_media_sync_bytes_reused
ultra_media_sync_bytes_remaining
ultra_media_sync_bytes_per_second
ultra_media_sync_eta_seconds
ultra_media_sync_torrent_total_bytes
ultra_media_sync_torrent_remaining_bytes
ultra_media_sync_torrent_eta_seconds
```

The expected target labels are `job="node"` and `instance="drlight:9100"`.
Per-torrent series also carry `torrent_id`, `title`, `category`, and
`queue_position` labels.

## Query Through Grafana

First discover the Prometheus UID:

```bash
PROM_UID=$(curl -fsS -u "$GRAFANA_USER:$GRAFANA_TOKEN" \
  "$GRAFANA_URL/api/datasources/name/Prometheus" | jq -r .uid)
```

Create a query payload:

```bash
jq -n --arg uid "$PROM_UID" '{
  queries: [{
    refId: "A",
    datasource: {type: "prometheus", uid: $uid},
    expr: "ultra_media_sync_torrent_eta_seconds{job=\"node\",instance=\"drlight:9100\"}",
    instant: true,
    range: false,
    intervalMs: 60000,
    maxDataPoints: 1000
  }],
  from: "now-3h",
  to: "now"
}' > /tmp/prom-query.json
curl -fsS -u "$GRAFANA_USER:$GRAFANA_TOKEN" \
  -H 'Content-Type: application/json' -X POST \
  "$GRAFANA_URL/api/ds/query" -d @/tmp/prom-query.json | jq .
```

Validate `results.A.frames` and frame field values. A query can be valid but
return no series because of wrong labels, time range, or a missing scrape.

## Debugging Checklist

1. Query the metric without labels.
2. Add `job` and `instance` filters.
3. Query `up{job="node",instance="drlight:9100"}`.
4. Inspect the Grafana datasource query response, including frame count.
5. Compare the dashboard's target expression with the working query.

## References

- [Prometheus HTTP API](https://prometheus.io/docs/prometheus/latest/querying/api/)
- [PromQL operators](https://prometheus.io/docs/prometheus/latest/querying/operators/)
