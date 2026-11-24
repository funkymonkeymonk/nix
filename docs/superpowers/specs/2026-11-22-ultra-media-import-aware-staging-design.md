# Import-Aware Ultra Media Staging

**Status:** Approved for implementation

## Intent

Prevent the Ultra staging worker from re-copying completed torrents after
their staged files have been removed following a successful Radarr, Sonarr, or
Lidarr import.

## Current problem

The worker already queries Arr library status for metrics, but staging only
reuses a torrent when its local staged files still exist and match the remote
manifest. Removing an imported staging tree therefore causes the next run to
copy it again.

## Approach

Use the existing Arr status collection as a staging gate. A torrent is skipped
only when at least one configured Arr application confirms that the torrent's
content is imported and no configured Arr application reports an import
failure or unknown status. An explicit failed import or unavailable API keeps
the torrent stageable, so failed imports can retry and transient API failures
do not suppress staging. Arr event names are case-insensitive.

The decision is keyed by Transmission's 40-character `hashString`, which is
the identifier Arr stores as `downloadId`; numeric Transmission IDs remain the
internal key for staging receipts and status maps. Missing or malformed hashes
produce unknown Arr status and must never suppress staging. The decision is
recorded in progress counters and tests. Receipts remain responsible for
remote cleanup authorization; they are not treated as proof of import.

## Goals

- Avoid re-copying successfully imported torrents after local cleanup.
- Continue retrying failed, partial, ambiguous, or API-unavailable imports.
- Preserve existing remote cleanup and receipt semantics.
- Keep status collection failure-closed.

## Non-goals

- Do not delete staged files automatically in this change.
- Do not move files directly into media libraries.
- Do not change Arr APIs or import behavior.

## Validation

Add unit coverage for imported, failed, unknown, and unavailable statuses,
including a completed torrent whose staging files are absent. Run the focused
Python test and the repository lint/build checks.
