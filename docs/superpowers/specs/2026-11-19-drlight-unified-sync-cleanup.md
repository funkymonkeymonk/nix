# Drlight Unified Download Sync and Seedbox Cleanup

## Intent

Use one scheduled Drlight job to sync completed Transmission payloads into Drlight staging and then remove seedbox torrents/files that meet the existing retention policy. The local Arr applications import from Drlight staging independently; Arr history or library import is not a seedbox-cleanup prerequisite.

## Behavior

- Keep the existing hourly schedule and one systemd worker. The worker stages downloads first, then processes cleanup receipts.
- A receipt is created only after every file for that torrent has been completely published to Drlight staging. A partial/failed transfer must not create a new receipt or authorize deletion.
- Cleanup may remove a torrent and its seedbox data only when its staged copy is verified, its retention rule qualifies, source mapping and unique ownership are proven, and final live-state revalidation succeeds.
- Preserve the existing retention rule: completion age is at least 240 hours since a valid positive Transmission `doneDate`, or torrent ratio is at least 3.0. Missing/invalid completion time fails closed unless the ratio independently qualifies. Arr import state is independent.
- Run cleanup after the staging attempt even if individual torrents failed; only receipts for successfully staged torrents can be considered, so one failed torrent does not block unrelated verified torrents.
- Preserve exact-path unique-owner checks. An incomplete inventory record with a safely known download directory blocks candidates under that directory; an invalid/unknown directory or empty inventory keeps ownership globally unknown. Never delete on uncertain or shared ownership.
- Preserve fail-closed handling for unknown paths, changed fingerprints, missing or mismatched staged files, and failed revalidation.
- Keep the cleanup queue private and per-torrent. The scheduled worker owns both sync and cleanup; remove the separate scheduled cleanup worker/timer and the now-redundant manual retry-reset worker.

## Observability

- Emit newline-delimited JSON events for staging progress, per-torrent stage success/failure, cleanup results, and a final combined run summary.
- Include aggregate counts and numeric progress only; do not log torrent IDs, names, source paths, library paths, endpoints, or secrets.
- Keep account-level seedbox disk usage in the existing Prometheus textfile metrics.
- Update the existing Grafana dashboard (preserve UID `drlight-ultra-media-sync`) to query the unified service and make transfer progress, retention/removal counts, failures, lag, and disk usage easy to distinguish.

## Non-goals

- Do not wait for local Arr imports or library placement before removing a qualifying seedbox copy.
- Do not change Drlight Arr import behavior.
- Do not deploy or apply changes to Drlight as part of this code change.
