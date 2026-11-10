"""Report-only retention decisions for Drlight's Ultra.cc cleanup controller.

Policy evaluation accepts normalized metadata and proof callbacks only. The
runtime entry point reports all unavailable evidence as unverified; no service
API, RPC, or removal operation is implemented here.
"""

import argparse
import fcntl
import json
import math
import os
import stat
from contextlib import contextmanager
from dataclasses import dataclass
from numbers import Real
from pathlib import Path
from typing import Any, Callable, Iterator, Mapping, Sequence


MIN_SEEDING_SECONDS = 240 * 60 * 60
MIN_TORRENT_RATIO = 3.0
MIN_PRIVATE_ACCOUNT_RATIO = 0.6
STAGING_ROOT = "/srv/media/.arr-staging"


@dataclass(frozen=True)
class ArrImportProof:
    """Normalized import proof; the runtime has no verified Arr adapter yet."""

    status: str
    imported_paths: frozenset[str]

    @classmethod
    def unverified(cls) -> "ArrImportProof":
        return cls(status="unverified", imported_paths=frozenset())

    @classmethod
    def verified(cls, imported_paths: Sequence[str]) -> "ArrImportProof":
        if not isinstance(imported_paths, (list, tuple, set, frozenset)) or any(
            not isinstance(path, str) or not path or "\0" in path
            for path in imported_paths
        ):
            return cls.unverified()
        return cls(status="verified", imported_paths=frozenset(imported_paths))


def _finite_number(value: Any) -> bool:
    """Return whether value is a finite real number (excluding booleans)."""
    if not isinstance(value, Real) or isinstance(value, bool):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def evaluate_retention(candidate: Mapping[str, Any]) -> dict[str, Any]:
    """Return an eligibility decision and safe reason codes for normalized metadata.

    Candidate schema:
      - ``complete``: true only when the torrent is complete.
      - ``seeding_seconds`` and ``torrent_ratio``: accumulated seeding duration
        in seconds and the torrent's upload/download ratio.
      - ``trackers``: records with ``classification`` equal to ``public`` or
        ``private``. Private records also require ``ratio_source_available``
        and ``account_ratio``.
      - ``files``: regular payload-file records with boolean ``mapped``,
        explicitly verified ``source_mapping_verified``, ``local_match`` (size
        and modification time), and ``shared_safe`` flags.

    The evaluator accepts no paths, URLs, credentials, or service handles. A
    missing or malformed safety fact fails closed. Private tracker checks are
    independent from the per-torrent sharing threshold.
    """
    reasons: list[str] = []

    def block(reason: str) -> None:
        if reason not in reasons:
            reasons.append(reason)

    if not isinstance(candidate, Mapping):
        return {"eligible": False, "reasons": ["candidate_malformed"]}

    if candidate.get("complete") is not True:
        block("incomplete_torrent")

    seeding_seconds = candidate.get("seeding_seconds")
    torrent_ratio = candidate.get("torrent_ratio")
    reached_seeding_limit = (
        _finite_number(seeding_seconds)
        and seeding_seconds >= MIN_SEEDING_SECONDS
    )
    reached_torrent_ratio = (
        _finite_number(torrent_ratio)
        and torrent_ratio >= MIN_TORRENT_RATIO
    )
    if not (reached_seeding_limit or reached_torrent_ratio):
        block("below_retention_threshold")

    trackers = candidate.get("trackers")
    if not isinstance(trackers, (list, tuple)) or not trackers:
        block("tracker_classification_unknown")
    else:
        for tracker in trackers:
            if not isinstance(tracker, Mapping):
                block("tracker_classification_unknown")
                continue

            classification = tracker.get("classification")
            if classification == "public":
                continue
            if classification != "private":
                block("tracker_classification_unknown")
                continue

            if tracker.get("ratio_source_available") is not True:
                block("private_ratio_unavailable")
                continue
            if "account_ratio" not in tracker or tracker.get("account_ratio") is None:
                block("private_ratio_missing")
                continue

            account_ratio = tracker.get("account_ratio")
            if not _finite_number(account_ratio):
                block("private_ratio_malformed")
            elif account_ratio < MIN_PRIVATE_ACCOUNT_RATIO:
                block("private_ratio_below_floor")

    files = candidate.get("files")
    if not isinstance(files, (list, tuple)) or not files:
        block("payload_files_missing")
    else:
        for payload_file in files:
            if not isinstance(payload_file, Mapping):
                block("file_metadata_invalid")
                continue
            if payload_file.get("mapped") is not True:
                block("file_unmapped")
            elif payload_file.get("source_mapping_verified") is not True:
                block("source_mapping_unverified")
            source_ownership_reason = _source_ownership_reason(payload_file, {payload_file.get("source_identity"): 1})
            if source_ownership_reason is not None:
                block(source_ownership_reason)
            if payload_file.get("local_match") is not True:
                block("local_file_mismatch")
            if payload_file.get("shared_safe") is not True:
                block("shared_file_unsafe")

    return {"eligible": not reasons, "reasons": reasons}


def _valid_integer(value: Any, *, nonnegative: bool = False) -> bool:
    return (
        isinstance(value, int)
        and not isinstance(value, bool)
        and (not nonnegative or value >= 0)
    )


def local_file_matches(file_record: Mapping[str, Any], observed: Any) -> bool:
    """Require exact regular-file size and nanosecond-mtime evidence."""
    if not isinstance(observed, Mapping):
        return False
    expected_size = file_record.get("expected_size")
    expected_mtime = file_record.get("expected_mtime_ns")
    actual_size = observed.get("size")
    actual_mtime = observed.get("mtime_ns")
    return (
        observed.get("regular_file") is True
        and _valid_integer(expected_size, nonnegative=True)
        and _valid_integer(actual_size, nonnegative=True)
        and _valid_integer(expected_mtime)
        and _valid_integer(actual_mtime)
        and expected_size == actual_size
        and expected_mtime == actual_mtime
    )


def _has_verified_source_mapping(candidate: Mapping[str, Any]) -> bool:
    files = candidate.get("files")
    if not isinstance(files, (list, tuple)) or not files:
        return True
    return all(
        not isinstance(file_record, Mapping)
        or file_record.get("mapped") is not True
        or file_record.get("source_mapping_verified") is True
        for file_record in files
    )


def _has_import_proof(candidate: Mapping[str, Any], proof: Any) -> bool:
    if not isinstance(proof, ArrImportProof) or proof.status != "verified":
        return False
    if not isinstance(proof.imported_paths, frozenset):
        return False
    files = candidate.get("files")
    if not isinstance(files, (list, tuple)) or not files:
        return False
    paths = []
    for file_record in files:
        if not isinstance(file_record, Mapping):
            return False
        path = file_record.get("local_path")
        if not isinstance(path, str) or not path or "\0" in path:
            return False
        paths.append(path)
    return set(paths).issubset(proof.imported_paths)


def _path_counts(candidates: Sequence[Any]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for candidate in candidates:
        if not isinstance(candidate, Mapping):
            continue
        files = candidate.get("files")
        if not isinstance(files, (list, tuple)):
            continue
        for file_record in files:
            if not isinstance(file_record, Mapping):
                continue
            path = file_record.get("local_path")
            if isinstance(path, str) and path and "\0" not in path:
                normalized_path = os.path.normpath(path)
                counts[normalized_path] = counts.get(normalized_path, 0) + 1
    return counts


def _source_identity_counts(candidates: Sequence[Any]) -> dict[str, int]:
    """Count opaque source identities without exposing them in reports.

    A runtime source inventory must use a stable source identity derived from
    the remote file's device/inode (or another verified ownership key) and
    include references from all torrent payloads and legacy library entries.
    """
    counts: dict[str, int] = {}
    for candidate in candidates:
        if not isinstance(candidate, Mapping):
            continue
        files = candidate.get("files")
        if not isinstance(files, (list, tuple)):
            continue
        for file_record in files:
            if not isinstance(file_record, Mapping):
                continue
            identity = file_record.get("source_identity")
            if isinstance(identity, str) and identity and "\0" not in identity:
                counts[identity] = counts.get(identity, 0) + 1
    return counts


def _source_ownership_reason(
    file_record: Mapping[str, Any], identity_counts: Mapping[str, int]
) -> str | None:
    """Require explicit verified, unique ownership across torrent/library paths."""
    identity = file_record.get("source_identity")
    owner_count = file_record.get("source_owner_count")
    if (
        file_record.get("source_ownership_verified") is not True
        or not isinstance(identity, str)
        or not identity
        or "\0" in identity
        or not _valid_integer(owner_count, nonnegative=True)
        or owner_count < 1
    ):
        return "source_ownership_unverified"
    if owner_count != 1 or identity_counts.get(identity, 0) != 1:
        return "source_file_shared"
    return None


def _candidate_source_ownership_reason(
    candidate: Mapping[str, Any], identity_counts: Mapping[str, int]
) -> str | None:
    files = candidate.get("files")
    if not isinstance(files, (list, tuple)) or not files:
        return None
    for file_record in files:
        if not isinstance(file_record, Mapping):
            return "source_ownership_unverified"
        reason = _source_ownership_reason(file_record, identity_counts)
        if reason is not None:
            return reason
    return None


def build_legacy_library_inventory_report(records: Sequence[Any]) -> dict[str, Any]:
    """Summarize normalized ownership fixtures without exposing identifiers.

    Each record supplies boolean ``transmission_owned`` and
    ``arr_library_owned`` facts. Optional opaque ``path_key`` and ``inode_key``
    values are compared only to find shared ownership; they are never included
    in the report. Missing or malformed ownership facts remain unknown. This
    function does not inspect or mutate the filesystem and never marks data
    deletable.
    """
    counts = {
        "transmission_only": 0,
        "legacy_arr_only": 0,
        "shared_path_or_inode": 0,
        "unknown_ownership": 0,
    }
    reasons: dict[str, int] = {}

    def report(record_count: int) -> dict[str, Any]:
        return {
            "mode": "report-only",
            "records": record_count,
            "counts": dict(counts),
            "deletable": 0,
            "reasons": dict(sorted(reasons.items())),
        }

    if not isinstance(records, Sequence) or isinstance(records, (str, bytes)):
        reasons["inventory_unverified"] = 1
        return report(0)

    normalized_records = list(records)
    classifications: list[tuple[str, str]] = []
    owner_facts: list[tuple[bool | None, bool | None] | None] = []
    overlaps: dict[str, dict[str, list[int]]] = {"path_key": {}, "inode_key": {}}

    for index, record in enumerate(normalized_records):
        if not isinstance(record, Mapping):
            classifications.append(("unknown_ownership", "ownership_unverified"))
            owner_facts.append(None)
            continue

        transmission_fact = record.get("transmission_owned")
        arr_fact = record.get("arr_library_owned")
        transmission_owned = (
            transmission_fact if type(transmission_fact) is bool else None
        )
        arr_library_owned = arr_fact if type(arr_fact) is bool else None
        owner_facts.append((transmission_owned, arr_library_owned))

        if transmission_owned is None or arr_library_owned is None:
            classifications.append(("unknown_ownership", "ownership_unverified"))
        elif transmission_owned and arr_library_owned:
            classifications.append(("shared_path_or_inode", "shared_path_or_inode"))
        elif transmission_owned:
            classifications.append(("transmission_only", "transmission_only"))
        elif arr_library_owned:
            classifications.append(("legacy_arr_only", "legacy_arr_only"))
        else:
            classifications.append(("unknown_ownership", "ownership_not_identified"))

        for key_name, index_by_key in overlaps.items():
            key = record.get(key_name)
            if isinstance(key, str) and key and "\0" not in key:
                index_by_key.setdefault(key, []).append(index)

    for index_by_key in overlaps.values():
        for matching_indices in index_by_key.values():
            has_transmission_owner = any(
                owner_facts[index] is not None
                and owner_facts[index][0] is True
                for index in matching_indices
            )
            has_arr_owner = any(
                owner_facts[index] is not None
                and owner_facts[index][1] is True
                for index in matching_indices
            )
            if has_transmission_owner and has_arr_owner:
                for index in matching_indices:
                    facts = owner_facts[index]
                    if (
                        facts is not None
                        and all(fact is not None for fact in facts)
                        and any(fact is True for fact in facts)
                    ):
                        classifications[index] = (
                            "shared_path_or_inode",
                            "shared_path_or_inode",
                        )

    for category, reason in classifications:
        counts[category] += 1
        reasons[reason] = reasons.get(reason, 0) + 1

    return report(len(normalized_records))


def build_cleanup_report(
    stage_succeeded: bool,
    candidates: Sequence[Mapping[str, Any]],
    *,
    arr_import_prover: Callable[[Mapping[str, Any]], ArrImportProof],
    local_file_verifier: Callable[[Mapping[str, Any]], Mapping[str, Any] | None],
) -> dict[str, Any]:
    """Return aggregate eligibility only; this function has no side effects."""
    candidate_count = len(candidates) if isinstance(candidates, Sequence) else 0
    if not isinstance(candidates, Sequence) or isinstance(candidates, (str, bytes)):
        candidates = ()
        candidate_count = 0
    if stage_succeeded is not True:
        return {
            "mode": "report-only",
            "candidates": candidate_count,
            "eligible": 0,
            "blocked": candidate_count,
            "reasons": {"staging_not_successful": candidate_count} if candidate_count else {},
        }

    path_counts = _path_counts(candidates)
    source_identity_counts = _source_identity_counts(candidates)
    reason_counts: dict[str, int] = {}
    eligible = 0

    for candidate in candidates:
        if not isinstance(candidate, Mapping):
            reasons = ["candidate_malformed"]
        elif candidate.get("runtime_config_available") is not True:
            reasons = ["runtime_configuration_unavailable"]
        elif candidate.get("rpc_available") is not True:
            reasons = ["transmission_state_unavailable"]
        elif candidate.get("tailscale_available") is not True:
            reasons = ["tailscale_unavailable"]
        elif not _has_verified_source_mapping(candidate):
            reasons = ["source_mapping_unverified"]
        elif (
            source_ownership_reason := _candidate_source_ownership_reason(
                candidate, source_identity_counts
            )
        ) is not None:
            reasons = [source_ownership_reason]
        else:
            try:
                proof = arr_import_prover(candidate)
            except Exception:
                proof = ArrImportProof.unverified()

            if not _has_import_proof(candidate, proof):
                reasons = ["arr_import_unverified"]
            else:
                candidate_with_proofs = dict(candidate)
                verified_files = []
                files = candidate.get("files")
                for file_record in files if isinstance(files, (list, tuple)) else ():
                    if not isinstance(file_record, Mapping):
                        verified_files.append(file_record)
                        continue
                    verified_file = dict(file_record)
                    path = verified_file.get("local_path")
                    try:
                        observation = local_file_verifier(verified_file)
                    except Exception:
                        observation = None
                    verified_file["local_match"] = local_file_matches(
                        verified_file, observation
                    )
                    normalized_path = (
                        os.path.normpath(path) if isinstance(path, str) else None
                    )
                    verified_file["shared_safe"] = (
                        normalized_path is not None
                        and path_counts.get(normalized_path, 0) == 1
                        and _source_ownership_reason(
                            verified_file, source_identity_counts
                        )
                        is None
                    )
                    verified_files.append(verified_file)
                candidate_with_proofs["files"] = verified_files
                decision = evaluate_retention(candidate_with_proofs)
                reasons = decision["reasons"]
                if decision["eligible"]:
                    eligible += 1

        for reason in reasons:
            reason_counts[reason] = reason_counts.get(reason, 0) + 1

    return {
        "mode": "report-only",
        "candidates": len(candidates),
        "eligible": eligible,
        "blocked": len(candidates) - eligible,
        "reasons": dict(sorted(reason_counts.items())),
    }


def _runtime_unverified_report() -> dict[str, Any]:
    """Describe unavailable state without reading secrets or contacting services."""
    return {
        "mode": "report-only",
        "inventory_status": "unavailable",
        "legacy_inventory_status": "unverified",
        "candidates": 0,
        "eligible": 0,
        "blocked": 0,
        "decision": "ineligible",
        "runtime_configuration_status": "unverified",
        "arr_import_status": "unverified",
        "source_ownership_status": "unverified",
        "transmission_state": "unverified",
        "tailscale_state": "unverified",
        "tracker_ratio_state": "unverified",
        "reasons": [
            "runtime_configuration_unavailable",
            "arr_import_unverified",
            "source_ownership_unverified",
            "transmission_state_unavailable",
            "tailscale_unavailable",
            "tracker_ratio_unavailable",
        ],
    }


@contextmanager
def _operation_lock(staging_root: str | Path = STAGING_ROOT) -> Iterator[None]:
    """Serialize report and staging runs using one lock under the staging root."""
    root = Path(staging_root).absolute()
    root.mkdir(parents=True, exist_ok=True)
    if root.is_symlink():
        raise OSError("staging root is not a directory")
    lock_path = root / ".operation.lock"
    flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(lock_path, flags, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise OSError("operation lock is not a regular file")
        with os.fdopen(descriptor, "r+") as lock_file:
            descriptor = -1
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            yield
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="explicitly request the only supported cleanup mode",
    )
    parser.parse_args(argv)
    try:
        with _operation_lock(STAGING_ROOT):
            report = _runtime_unverified_report()
    except OSError:
        print("cleanup failed reason=operation_lock_unavailable")
        return 1
    print("cleanup " + json.dumps(report, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
