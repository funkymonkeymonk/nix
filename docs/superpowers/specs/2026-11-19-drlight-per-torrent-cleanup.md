# Drlight Per-Torrent Cleanup and Completion-Age Retention

## Goal

Allow cleanup to continue for torrents whose source ownership is proven, even when unrelated Transmission inventory records have invalid path metadata, and base the 240-hour retention threshold on Transmission `doneDate` rather than `secondsSeeding`.

## Design

`build_cleanup_candidates` currently treats inventory validity as one global boolean. Any malformed torrent path makes every candidate's owner count unknown. Replace that global barrier with scoped uncertainty:

- Count ownership for every independently valid normalized source path.
- If a record has a valid absolute download directory but incomplete/invalid file paths, mark only that download directory as an incomplete ownership scope. Candidates below that directory remain blocked; candidates outside it can be evaluated from complete ownership evidence.
- If a record's download directory is missing or unsafe, or the inventory is empty, its possible ownership scope cannot be bounded; keep all deletion blocked.
- Preserve exact-path unique-owner checks, Arr import proof, local-file revalidation, and all other cleanup gates. Never infer ownership from missing metadata.
- Qualify retention when `now - doneDate >= 240 hours` or `uploadRatio >= 3.0`. Transmission 4.0.5 on Drlight reports `secondsSeeding=0` for stopped torrents even when `doneDate` is weeks old; upstream fixed that stopped-torrent accounting bug in 4.0.6. Missing or invalid `doneDate` remains unknown and fails closed unless the ratio threshold independently qualifies.

## Expected Behavior

A bad record in `/seedbox/other` does not block a fully verified cleanup candidate in `/seedbox/complete`. A bad record in the candidate's own directory still blocks it. An invalid or unknown download directory still blocks all candidates because shared ownership cannot be excluded safely. A torrent completed at least 240 hours ago may pass the age threshold even if its seeding counter is zero; a recent completion with a ratio below 3.0 remains blocked.

## Constraints

- Never delete remote data when an unbounded or overlapping ownership uncertainty remains.
- Continue emitting aggregate reason counts only; do not log source paths, torrent IDs, names, endpoints, or secrets.
- Preserve per-torrent queue processing and existing revalidation/import proofs.
