# Drlight Per-Torrent Cleanup Isolation

## Goal

Allow cleanup to continue for torrents whose source ownership is proven, even when unrelated Transmission inventory records have invalid path metadata.

## Design

`build_cleanup_candidates` currently treats inventory validity as one global boolean. Any malformed torrent path makes every candidate's owner count unknown. Replace that global barrier with scoped uncertainty:

- Count ownership for every independently valid normalized source path.
- If a record has a valid absolute download directory but incomplete/invalid file paths, mark only that download directory as an incomplete ownership scope. Candidates below that directory remain blocked; candidates outside it can be evaluated from complete ownership evidence.
- If a record's download directory is missing or unsafe, or the inventory is empty, its possible ownership scope cannot be bounded; keep all deletion blocked.
- Preserve exact-path unique-owner checks, Arr import proof, local-file revalidation, and all other cleanup gates. Never infer ownership from missing metadata.

## Expected Behavior

A bad record in `/seedbox/other` does not block a fully verified cleanup candidate in `/seedbox/complete`. A bad record in the candidate's own directory still blocks it. An invalid or unknown download directory still blocks all candidates because shared ownership cannot be excluded safely.

## Constraints

- Never delete remote data when an unbounded or overlapping ownership uncertainty remains.
- Continue emitting aggregate reason counts only; do not log source paths, torrent IDs, names, endpoints, or secrets.
- Preserve per-torrent queue processing and existing revalidation/import proofs.
