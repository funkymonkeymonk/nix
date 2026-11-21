# Grafana Dashboard Change Log

This log records API-only changes made while developing the Grafana dashboard.
The API development dashboard is `drlight-ultra-media-sync-dev`.

## 2026-11-21

- Renamed the queue progress display from **published** to **staged**.
- Kept the underlying metric name as `ultra_media_sync_torrents_published`.
- Follow-up: decide whether the sync process should expose a new metric name.
- When the metric name changes, update the exporter, dashboard queries, tests,
  and any alert or recording-rule references together.

The provisioned production dashboard remains the durable target for later Nix
updates. API development changes do not update `modules/nixos/grafana.nix`.
