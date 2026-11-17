# Ultra Media Progress and Concurrent Per-Torrent Cleanup

## Goal

Report useful staging progress and begin safe cleanup as individual torrents finish staging, instead of waiting for the complete staging batch.

## Current behavior

The staging controller fetches a Transmission snapshot, copies each completed torrent's files into a temporary directory, and publishes that torrent's files only after all of its transfers succeed. It currently holds one exclusive operation lock around the whole run, emits no progress until the final summary, and writes one success marker only after the entire run succeeds. Systemd starts cleanup through the stage service's `OnSuccess` relationship. Cleanup consumes the single marker, re-fetches Transmission and Arr state, checks all cleanup gates, and removes torrents with Transmission's `torrent-remove` operation.

## Design

### Progress reporting

- Plan the current staging run from the Transmission snapshot, including counts and bytes for completed, path-mapped files that the staging policy will copy. The plan is scoped to that snapshot; later completions belong to the next stage run.
- Emit one aggregate structured progress event to the systemd journal every 60 seconds, plus start, completion, deferred, and failure summaries.
- Include run elapsed time, torrents/files completed and total, bytes copied and total, current rate, and an ETA when the total and a stable rate are available. Keep ETA absent/unknown until it is meaningful.
- Emit no torrent names, IDs, media paths, tracker details, RPC endpoints, or credentials. The existing Vector/Loki/Grafana path displays aggregate progress and ETA.

### Per-torrent staging receipts

- Preserve the existing atomic unit: a torrent is staged only after every required file for that torrent has transferred and its files have been published successfully.
- Use a stable, hash-named in-progress workspace per torrent and a private manifest fingerprint. Rsync retries with the same manifest reuse `.rsync-partial`; a changed manifest invalidates that workspace. Incomplete workspace files are never published to Arr roots.
- On retry, reuse any already-published stage file only after a strict-SSH remote stat confirms it is a regular file with matching size and nanosecond mtime. Do not checksum. Missing/mismatched files are recopied; cleanup still re-verifies imports before deletion.
- After successful publication, write an idempotent per-torrent receipt to a private queue. A receipt contains only a schema version, torrent ID, a fingerprint of the source file manifest and mapping, and timestamps; it contains no media paths or names.
- Receipts live under `/var/lib/ultra-media/cleanup-queue` in a systemd `StateDirectory` with mode `0700`; each file is written atomically and receipts survive service restarts. A receipt contains a schema version, torrent ID, SHA-256 fingerprint of the normalized source file manifest and mapping, stage time, retry count, and next-attempt time. Raw media paths are not stored.
- Incomplete or failed torrent transfers produce no receipt. A later failure in a different torrent does not invalidate receipts already written for successful torrents.

### Concurrent cleanup worker

- Replace whole-run `OnSuccess` cleanup with a one-minute cleanup queue timer, enabled only when cleanup is enabled. The oneshot worker drains due receipts while staging continues and exits quickly when no receipts are due.
- Stage and cleanup use per-torrent locks under `/run/ultra-media/locks`, named by a one-way hash of the torrent ID. Cleanup acquires locks nonblocking: if staging holds that torrent's lock, defer it and continue to other receipts. A separate queue lock protects receipt updates. Operations on the same torrent cannot overlap, while independent torrents can stage and clean concurrently.
- For each receipt, re-fetch the full Transmission inventory and Arr import state. Compute path/source ownership across the full inventory before filtering to queued torrent IDs; do not clean an unqueued torrent.
- Preserve every existing deletion gate: complete torrent, retention threshold, tracker policy, all files imported and verified by size/mtime, unique source ownership, and immediate fresh revalidation before removal.
- Remove a torrent only after all of that torrent's files are staged and verified. Transmission's current removal operation deletes an entire torrent payload; individual files within a torrent are not deleted independently.
- If Arr import or another transient prerequisite is not ready, retain the receipt and retry with exponential backoff starting at 60 seconds and capped at one hour. Policy holds such as the retention threshold, tracker policy, or shared ownership retry no more often than hourly. If a torrent is already absent, acknowledge the receipt without issuing a removal. Stale/mismatched fingerprints fail closed.
- A worker pass may process multiple due receipts, but it does not hold a global stage lock while checking Arr state or waiting for retries. Same-torrent locking covers receipt matching, fresh revalidation, and removal.
- Keep logs aggregate-only and never log receipt IDs or fingerprints.

## Failure and concurrency behavior

A successful torrent may be cleaned even if a different torrent later fails staging; this is the required consequence of per-torrent queueing. A failed or partial torrent never receives a receipt. Same-torrent locks, source-ownership checks over the full current Transmission inventory, fresh revalidation, atomic staging publication, and idempotent receipts prevent cleanup from racing an unfinished transfer or deleting shared source data. A system restart preserves pending queue receipts and matching in-progress torrent workspaces, but every receipt is still revalidated before a destructive action. The currently active legacy run uses random workspaces without manifests; if interrupted, its incomplete torrent must be recopied from the untouched seedbox source, while any previously published files remain intact.

## Non-goals

- Deleting individual files within a torrent.
- Weakening Arr import, size/mtime, source-ownership, tracker, retention, or fresh-state checks.
- Logging per-torrent names, paths, IDs, or credentials.
- Replacing Transmission's documented torrent-removal RPC.

## Validation

Tests must prove 60-second aggregate progress and ETA behavior; no sensitive values in events; receipts are emitted only after a torrent is fully published; partial transfers do not enqueue cleanup; queue processing is restricted to fresh, matching receipts; shared source files remain protected; deferred imports are retried without blocking staging; same-torrent operations serialize while independent torrents can overlap; cleanup remains disabled/report-only when configured off; and every destructive path retains the existing gates.
