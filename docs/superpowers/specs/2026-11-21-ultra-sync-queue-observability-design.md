# Ultra Sync Queue Observability Design

## Intent

Expose the live seedbox synchronization queue in Prometheus/Grafana so the
operator can see the current job, queued torrents, sizes, transfer progress,
and estimated completion times.

## Design

The sync worker will publish an aggregate/per-torrent Prometheus textfile
snapshot alongside the existing seedbox storage metrics. Metrics will include
current run state, queue position, torrent title, category, total bytes,
remaining bytes, completion timestamp when known, and an ETA derived from the
current transfer rate and ordered queue. The snapshot will be written
atomically and replaced at each progress update or safe periodic interval.

Grafana will add:

- current sync state, progress, rate, and overall ETA stat panels;
- a sortable per-torrent table showing queue position, title, category, size,
  remaining bytes, and estimated completion;
- explicit unavailable values when the rate or torrent size is unknown;
- stale-data handling based on the exporter sample timestamp.

Torrent names are acceptable Prometheus labels because this is an internal,
access-controlled home Prometheus/Grafana deployment. Full local or remote
filesystem paths and credentials remain excluded.

## Constraints

- Preserve atomic staging and cleanup behavior.
- Do not expose secret values or full filesystem paths.
- Keep metric cardinality bounded to the current queue and replace old rows.
- Add tests for queue ordering, ETA calculation, malformed/unknown values, and
  atomic metric publication.
