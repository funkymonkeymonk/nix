# Drlight Cleanup Retry Reset

## Intent

Provide an explicit, operator-triggered way to make every valid queued cleanup receipt due immediately, so a full retry can be started without waiting for each receipt's backoff deadline.

## Behavior

- Add a one-shot reset operation that sets each valid receipt's `next_attempt_ns` to its `staged_at_ns`.
- Preserve attempt counts, receipt IDs, fingerprints, and all other fields.
- Skip malformed, symlinked, or concurrently replaced receipts; update valid entries atomically under the existing cleanup queue lock.
- Expose the operation as a manual systemd oneshot service. Starting it resets retry deadlines only; starting the existing cleanup service then evaluates the due receipts.
- The cleanup process continues to apply all existing retention, Transmission ownership, Arr-import, local-file match, per-torrent isolation, and final revalidation safeguards. Resetting retry times does not authorize deletion.

## Approaches

- **One-shot retry-deadline reset (selected):** explicit, auditable queue operation; reuses the existing due-receipt path and keeps retry timing state valid.
- **Persistent semaphore:** simpler trigger, but adds a marker lifecycle and crash/replay semantics.
- **Set deadlines to a sentinel such as `-1`:** rejected because receipt validation requires a retry deadline at or after `staged_at_ns`; invalid receipts would be skipped.

## Operator flow

Run `systemctl start ultra-media-cleanup-reset-retries.service`, then `systemctl start ultra-media-cleanup.service` on the target. The first unit changes scheduling only; the second performs normal evaluation and deletion checks.
