# Drlight Sync Lag and Remote Storage Monitoring

## Goal

Make staging progress trustworthy, prioritize completed torrents oldest-first, show the age of the unstaged backlog, and graph/alert on the seedbox account's storage usage.

## Current behavior

The staging plan follows Transmission's returned order and does not request completion timestamps. The Grafana dashboard displays structured transfer events, but the rsync runner discards stdout while reading stderr; an isolated rsync probe confirmed `--info=progress2` emits its progress on stdout. Drlight has a one-minute cleanup timer and an existing Prometheus/Alertmanager stack. A read-only `df` probe sees the seedbox's shared filesystem, not the user's quota. Ultra's documented `app-stats show -s disk -t hour -c 1` reports account-level usage in decimal GB; a read-only sample reported 4,000 GB.

## Design

- Capture rsync progress from stdout and discard stderr diagnostics. Only parsed numeric byte counts may reach progress callbacks.
- Request Transmission's `doneDate` and order otherwise-stageable completed torrents ascending by completion time. The `time behind` metric is the age of the oldest dated candidate not yet staged: `now - oldest_pending_doneDate`. It can rise while a torrent is transferring and should step down when that older torrent completes; new completions join the next snapshot.
- A completed, mapped torrent without a valid positive `doneDate` is not staged in that run and increments an aggregate unknown-order count. While such candidates exist, backlog age is reported as unknown rather than claiming the sync is fully ordered/caught up. Dated torrents continue oldest-first.
- Query Ultra's account-level disk usage with `app-stats show -s disk -t hour -c 1` through the existing strict-SSH cleanup worker. The cleanup timer runs every minute, including when its receipt queue is empty. Emit an aggregate remote-disk usage event and atomically update a Prometheus node-exporter textfile metric; probe failure must not block cleanup and must be observable.
- Configure nominal capacity as 4,000,000,000,000 bytes and warning threshold as 3,000,000,000,000 bytes (decimal TB). Grafana shows remote used/capacity and the threshold. Prometheus evaluates the warning and routes it through the existing Alertmanager null receiver; no external notification endpoint or secret is added.
- If disk-usage data is stale or unavailable, Grafana must not display it as safely below threshold; expose a separate stale/unavailable alert state.

## Approaches considered

- **Backlog age vs transfer ETA:** use oldest pending completion age as the requested "time behind"; preserve transfer ETA as a separate metric.
- **`df` vs provider usage:** use `app-stats`, because `df` reports the shared host filesystem (about 21.99 TB in the current probe), not the user's 4 TB allocation.
- **Grafana/Loki alert vs Prometheus/Alertmanager:** export a small aggregate textfile metric so the warning uses the existing Prometheus alert rules and null Alertmanager route.
- **Cleanup worker vs a new poller:** sample from the already-enabled one-minute cleanup worker, avoiding another timer/service while still collecting usage when staging is idle.

## Constraints

- Preserve existing whole-torrent staging and cleanup safety, per-torrent locking, source ownership, retry, Arr import, and revalidation behavior.
- Never log torrent IDs, torrent/file names, media paths, remote endpoints, or credentials.
- Missing completion times are not silently assigned an arbitrary chronological position.
- Do not add non-null alert receivers or hard-code webhook credentials.
