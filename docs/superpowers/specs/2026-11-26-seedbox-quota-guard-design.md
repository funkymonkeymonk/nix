# Seedbox Quota Guard

## Intent

Prevent Transmission from crashing when the Ultra account quota is exhausted by
pausing downloads before the quota limit, while leaving completed torrents
available to seed. Review live usage and guard activity after one week in
production.

## Approaches

- Tighten retention cleanup only: useful, but it cannot stop active downloads
  from consuming space before cleanup runs.
- Add quota control to the hourly sync job: fewer moving parts, but up to an
  hour of delay is too slow for a safety guard.
- **Add a separate Drlight-managed quota guard (selected):** poll live account
  usage every minute and control only downloads through Transmission RPC. This
  is the fastest option managed by this repository without changing the
  provider-managed seedbox configuration.

## Design

- Read current account usage using `quota -p` over the existing strict SSH
  connection; do not use the hourly `app-stats` sample for the control decision.
- At **3.8 TB decimal**, stop active or queued incomplete downloads. Do not stop
  completed torrents, so they can continue seeding.
- Keep those downloads paused until usage falls below **3.5 TB decimal**. Resume
  only torrents recorded as paused by the guard; torrents that were already
  stopped remain untouched.
- Persist the guard's state on Drlight. If the quota probe or RPC is unavailable
  or malformed, do not resume torrents based on stale or unknown usage.
- Resolve the guard's cleanup and staging runtime helpers from the configured
  Python path when the guard entrypoint is packaged separately; missing helpers
  remain fail-closed.
- Keep the existing hourly staging and verified cleanup policy responsible for
  freeing space. The guard never deletes payloads or changes seeding behavior.
- Export live usage, guard state, and pause/resume/failure counts for a week-one
  review in Grafana.

## Constraints and non-goals

- The current Transmission outage cannot be corrected by an RPC guard while
  the RPC endpoint is refusing connections. Free enough space and restore
  Transmission once before enabling the production trial.
- This change does not alter Ultra's provider-managed service configuration,
  directly delete seedbox files, or weaken the existing staged-copy and cleanup
  safety checks.
- The 200 GB trigger reserve is an initial conservative trial value. Review
  observed peak usage, pause duration, and recovery behavior after one week and
  adjust only from production measurements.
