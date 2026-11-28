# Aggressive Seedbox Cleanup Policy

## Intent

Reduce repeated seedbox-full failures by allowing Drlight to remove verified
completed torrents sooner: after **24 hours** since completion or at an upload
ratio of **1.0**, whichever comes first.

## Approaches

- Hard-code the new thresholds: smallest change, but difficult to audit or tune.
- Store thresholds in runtime configuration: flexible, but less declarative and
  harder to review.
- **Use explicit Nix options (selected):** expose the thresholds in the cleanup
  module, pass them to the worker, and set Drlight's values declaratively.

## Design

Add positive Nix options for completion age (hours) and torrent ratio. Pass both
values as command-line arguments to the unified sync/cleanup worker and through
to the retention evaluator. Keep every existing safety gate unchanged:
completed and mapped torrent, verified staged copy, unique ownership, local
size/mtime match, tracker policy, and final live revalidation. Add focused tests
covering the configured thresholds and the generated service arguments.

This change modifies configuration only. It does not deploy to Drlight or
remove existing seedbox data.
