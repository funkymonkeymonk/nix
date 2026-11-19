"""Retention policy and guarded Ultra.cc seedbox cleanup controller.

Cleanup consumes per-torrent staging receipts and uses Transmission RPC only
after local Arr import and size/mtime proofs; the Drlight library is never
mutated by this controller.
"""

import argparse
import importlib.util
import json
import math
import os
import posixpath
import stat
import subprocess
import sys
import time
import tempfile
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen
from contextlib import ExitStack, nullcontext
from ultra_media_file_stat import (
    make_remote_disk_usage_probe,
    make_remote_source_stat,
    parse_remote_stat,
)
from dataclasses import dataclass
from numbers import Real
from pathlib import Path
from typing import Any, Callable, Iterator, Mapping, Sequence


MIN_SEEDING_SECONDS = 240 * 60 * 60
MIN_TORRENT_RATIO = 3.0
MIN_PRIVATE_ACCOUNT_RATIO = 0.6
STAGING_ROOT = "/srv/media/.arr-staging"
RUNTIME_ROOT = "/run/ultra-media"
CLEANUP_QUEUE_ROOT = "/var/lib/ultra-media/cleanup-queue"
REMOTE_DISK_METRICS_PATH = "/run/ultra-media-metrics/ultra-seedbox.prom"
REMOTE_DISK_CAPACITY_BYTES = 4_000_000_000_000
REMOTE_DISK_WARNING_THRESHOLD_BYTES = 3_000_000_000_000


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


def write_remote_disk_metrics(
    metrics_path: str | Path,
    *,
    used_bytes: int | None,
    capacity_bytes: int,
    warning_threshold_bytes: int,
    sample_timestamp_seconds: int,
) -> None:
    """Atomically publish aggregate seedbox usage for node_exporter's textfile collector."""
    if (
        used_bytes is not None
        and (not isinstance(used_bytes, int) or isinstance(used_bytes, bool) or used_bytes < 0)
    ):
        raise ValueError("remote disk usage is invalid")
    if (
        not isinstance(capacity_bytes, int)
        or isinstance(capacity_bytes, bool)
        or capacity_bytes <= 0
        or not isinstance(warning_threshold_bytes, int)
        or isinstance(warning_threshold_bytes, bool)
        or warning_threshold_bytes <= 0
        or not isinstance(sample_timestamp_seconds, int)
        or isinstance(sample_timestamp_seconds, bool)
        or sample_timestamp_seconds <= 0
    ):
        raise ValueError("remote disk metric configuration is invalid")

    path = Path(metrics_path)
    if path.is_symlink():
        raise OSError("remote disk metrics destination must not be a symlink")
    try:
        existing = os.lstat(path)
    except FileNotFoundError:
        existing = None
    if existing is not None and not stat.S_ISREG(existing.st_mode):
        raise OSError("remote disk metrics destination must be a regular file")

    lines = [
        "# HELP ultra_seedbox_storage_capacity_bytes Configured seedbox account capacity in bytes.",
        "# TYPE ultra_seedbox_storage_capacity_bytes gauge",
        f"ultra_seedbox_storage_capacity_bytes {capacity_bytes}",
        "# HELP ultra_seedbox_storage_warning_threshold_bytes Configured seedbox storage warning threshold in bytes.",
        "# TYPE ultra_seedbox_storage_warning_threshold_bytes gauge",
        f"ultra_seedbox_storage_warning_threshold_bytes {warning_threshold_bytes}",
        "# HELP ultra_seedbox_storage_probe_success Whether the latest seedbox storage probe succeeded.",
        "# TYPE ultra_seedbox_storage_probe_success gauge",
        f"ultra_seedbox_storage_probe_success {1 if used_bytes is not None else 0}",
        "# HELP ultra_seedbox_storage_sample_timestamp_seconds Unix time of the latest storage probe.",
        "# TYPE ultra_seedbox_storage_sample_timestamp_seconds gauge",
        f"ultra_seedbox_storage_sample_timestamp_seconds {sample_timestamp_seconds}",
    ]
    if used_bytes is not None:
        lines.extend(
            [
                "# HELP ultra_seedbox_storage_used_bytes Account-level seedbox storage used in bytes.",
                "# TYPE ultra_seedbox_storage_used_bytes gauge",
                f"ultra_seedbox_storage_used_bytes {used_bytes}",
            ]
        )

    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="ascii",
            dir=path.parent,
            prefix=".ultra-seedbox-",
            suffix=".prom",
            delete=False,
        ) as metrics_file:
            temporary_path = Path(metrics_file.name)
            os.fchmod(metrics_file.fileno(), 0o640)
            metrics_file.write("\n".join(lines) + "\n")
            metrics_file.flush()
            os.fsync(metrics_file.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
        directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


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


def _path_is_within(path: str, roots: Sequence[str]) -> bool:
    normalized = os.path.normpath(path)
    for root in roots:
        if not isinstance(root, str) or not root.startswith("/") or "\0" in root:
            continue
        normalized_root = os.path.normpath(root)
        try:
            if os.path.commonpath((normalized_root, normalized)) == normalized_root:
                return True
        except ValueError:
            continue
    return False


def build_import_path_map(
    records: Sequence[Any],
    library_roots: Sequence[str],
    *,
    staging_root: str = STAGING_ROOT,
) -> dict[str, str]:
    """Map imported staging paths to unique library paths from Arr history."""
    if not isinstance(records, Sequence) or isinstance(records, (str, bytes)):
        return {}
    if not isinstance(library_roots, Sequence) or isinstance(library_roots, (str, bytes)):
        return {}
    normalized_stage_root = os.path.normpath(staging_root)
    allowed_events = {"downloadFolderImported", "trackFileImported"}
    mappings: dict[str, str] = {}
    ambiguous: set[str] = set()

    for record in records:
        if not isinstance(record, Mapping):
            raise ValueError("arr_history_malformed")
        if record.get("eventType") not in allowed_events:
            continue
        data = record.get("data")
        if not isinstance(data, Mapping):
            raise ValueError("arr_history_malformed")
        dropped_path = data.get("droppedPath")
        imported_path = data.get("importedPath")
        if (
            not isinstance(dropped_path, str)
            or not dropped_path.startswith("/")
            or "\0" in dropped_path
            or not isinstance(imported_path, str)
            or not imported_path.startswith("/")
            or "\0" in imported_path
        ):
            raise ValueError("arr_history_malformed")
        dropped_path = os.path.normpath(dropped_path)
        imported_path = os.path.normpath(imported_path)
        if not _path_is_within(dropped_path, [normalized_stage_root]):
            continue
        if not _path_is_within(imported_path, library_roots):
            raise ValueError("arr_history_malformed")
        if dropped_path in ambiguous:
            continue
        previous = mappings.get(dropped_path)
        if previous is not None and previous != imported_path:
            mappings.pop(dropped_path, None)
            ambiguous.add(dropped_path)
        else:
            mappings[dropped_path] = imported_path

    imported_destinations: dict[str, list[str]] = {}
    for dropped_path, imported_path in mappings.items():
        imported_destinations.setdefault(imported_path, []).append(dropped_path)
    for dropped_paths in imported_destinations.values():
        if len(dropped_paths) > 1:
            for dropped_path in dropped_paths:
                mappings.pop(dropped_path, None)

    return mappings


def fetch_arr_import_paths(
    arr_apis: Sequence[Mapping[str, Any]],
    library_roots: Sequence[str],
    *,
    page_size: int = 1000,
    request_timeout: float = 20,
) -> dict[str, str]:
    """Read paged local Arr histories and map only supported import events."""
    if not isinstance(arr_apis, Sequence) or isinstance(arr_apis, (str, bytes)) or not arr_apis:
        raise RuntimeError("arr_state_unavailable")
    if not isinstance(page_size, int) or isinstance(page_size, bool) or page_size < 1:
        raise RuntimeError("arr_state_unavailable")

    all_records: list[Mapping[str, Any]] = []
    for app in arr_apis:
        if not isinstance(app, Mapping):
            raise RuntimeError("arr_state_unavailable")
        base_url = app.get("baseUrl")
        api_key_path = app.get("apiKeyFile")
        if not isinstance(base_url, str) or not isinstance(api_key_path, str):
            raise RuntimeError("arr_state_unavailable")
        try:
            parsed = urlsplit(base_url)
            if (
                parsed.scheme != "http"
                or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}
                or parsed.username is not None
                or parsed.password is not None
                or parsed.query
                or parsed.fragment
                or parsed.port is None
            ):
                raise RuntimeError("arr_state_unavailable")
            api_key = Path(api_key_path).read_text(encoding="utf-8").strip()
        except (OSError, UnicodeError, ValueError):
            raise RuntimeError("arr_state_unavailable") from None
        if not api_key or any(character in api_key for character in "\r\n\0"):
            raise RuntimeError("arr_state_unavailable")

        page = 1
        total_records: int | None = None
        while True:
            query = urlencode(
                {
                    "page": page,
                    "pageSize": page_size,
                    "sortKey": "date",
                    "sortDirection": "descending",
                }
            )
            request = Request(
                base_url.rstrip("/") + "/history?" + query,
                headers={"X-Api-Key": api_key, "Accept": "application/json"},
                method="GET",
            )
            try:
                with urlopen(request, timeout=request_timeout) as response:
                    payload = json.load(response)
            except (HTTPError, URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError):
                raise RuntimeError("arr_state_unavailable") from None
            if not isinstance(payload, Mapping):
                raise RuntimeError("arr_state_unavailable")
            records = payload.get("records")
            total = payload.get("totalRecords")
            if (
                not isinstance(records, list)
                or not isinstance(total, int)
                or isinstance(total, bool)
                or total < 0
            ):
                raise RuntimeError("arr_state_unavailable")
            if total_records is None:
                total_records = total
            elif total != total_records:
                raise RuntimeError("arr_state_unavailable")
            if any(not isinstance(record, Mapping) for record in records):
                raise RuntimeError("arr_state_unavailable")
            all_records.extend(records)
            if not records:
                if page * page_size < total_records:
                    raise RuntimeError("arr_state_unavailable")
                break
            if page * page_size >= total_records:
                break
            page += 1
            if page > 10000:
                raise RuntimeError("arr_state_unavailable")

    return build_import_path_map(all_records, library_roots)


def build_cleanup_candidates(
    torrents: Sequence[Mapping[str, Any]],
    mappings: Any,
    imported_paths: Mapping[str, str],
    *,
    staging_root: str,
    path_mapper: Callable[..., str],
) -> list[dict[str, Any]]:
    """Normalize RPC torrents with exact source, staging, and Arr paths."""
    if not isinstance(torrents, Sequence) or isinstance(torrents, (str, bytes)):
        return []
    source_path_counts: dict[str, int] = {}
    inventory_valid = bool(torrents)
    for torrent in torrents:
        if not isinstance(torrent, Mapping):
            inventory_valid = False
            continue
        directory = torrent.get("download_directory")
        paths = torrent.get("file_paths")
        if (
            torrent.get("file_paths_valid") is not True
            or not isinstance(directory, str)
            or not isinstance(paths, list)
            or not paths
            or not directory.startswith("/")
            or ".." in directory.split("/")
            or "\0" in directory
        ):
            inventory_valid = False
            continue
        normalized_directory = posixpath.normpath(directory)
        for file_path in paths:
            if (
                not isinstance(file_path, str)
                or not file_path
                or file_path.startswith("/")
                or ".." in file_path.split("/")
                or "\0" in file_path
            ):
                inventory_valid = False
                continue
            source_path = posixpath.normpath(posixpath.join(normalized_directory, file_path))
            source_path_counts[source_path] = source_path_counts.get(source_path, 0) + 1

    candidates: list[dict[str, Any]] = []
    for torrent in torrents:
        if not isinstance(torrent, Mapping):
            continue
        raw_candidate = torrent.get("candidate")
        candidate = dict(raw_candidate) if isinstance(raw_candidate, Mapping) else {}
        file_paths = torrent.get("file_paths")
        file_sizes = torrent.get("file_sizes")
        directory = torrent.get("download_directory")
        paths_valid = (
            torrent.get("file_paths_valid") is True
            and isinstance(file_paths, list)
            and isinstance(directory, str)
        )
        normalized_directory = posixpath.normpath(directory) if paths_valid else ""
        sizes_valid = (
            torrent.get("file_sizes_valid") is True
            and isinstance(file_sizes, list)
            and len(file_sizes) == len(file_paths)
        )
        raw_files = candidate.get("files")
        raw_files = raw_files if isinstance(raw_files, list) else []
        file_count = max(len(file_paths) if isinstance(file_paths, list) else 0, len(raw_files))
        files = []

        for index in range(file_count):
            source_file = dict(raw_files[index]) if index < len(raw_files) and isinstance(raw_files[index], Mapping) else {}
            mapped = False
            staged_path = None
            remote_path = None
            local_path = None
            source_size = file_sizes[index] if sizes_valid and index < len(file_sizes) else None
            source_identity = None
            owner_count = None
            if paths_valid and index < len(file_paths):
                file_path = file_paths[index]
                try:
                    remote_path = posixpath.normpath(posixpath.join(normalized_directory, file_path))
                    staged_path = path_mapper(
                        normalized_directory,
                        file_path,
                        mappings,
                        staging_root=staging_root,
                    )
                    mapped = True
                    source_identity = remote_path
                    owner_count = (
                        source_path_counts.get(remote_path, 0)
                        if inventory_valid
                        else None
                    )
                    local_path = imported_paths.get(staged_path)
                except Exception:
                    mapped = False
            source_file.update(
                {
                    "mapped": mapped,
                    "source_mapping_verified": mapped,
                    "source_identity": source_identity,
                    "source_ownership_verified": mapped and owner_count is not None,
                    "source_owner_count": owner_count,
                    "staged_path": staged_path,
                    "remote_path": remote_path,
                    "local_path": local_path,
                    "expected_size": source_size,
                    "expected_mtime_ns": None,
                    "local_match": False,
                    "shared_safe": mapped,
                }
            )
            files.append(source_file)

        candidate["files"] = files
        candidate["torrent_id"] = torrent.get("id")
        candidate["runtime_config_available"] = True
        candidate["rpc_available"] = True
        candidate["arr_state_available"] = True
        candidate["remote_download_directory"] = directory
        candidate["remote_file_paths"] = list(file_paths) if isinstance(file_paths, list) else []
        candidates.append(candidate)

    return candidates


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


def make_arr_import_prover(
    source_stat: Callable[[str], Mapping[str, Any] | None],
) -> Callable[[Mapping[str, Any]], ArrImportProof]:
    """Build an import proof only when each imported file matches its source."""
    def prove(candidate: Mapping[str, Any]) -> ArrImportProof:
        files = candidate.get("files") if isinstance(candidate, Mapping) else None
        if not isinstance(files, (list, tuple)) or not files:
            return ArrImportProof.unverified()
        imported_paths = []
        for file_record in files:
            if not isinstance(file_record, dict):
                return ArrImportProof.unverified()
            source_path = file_record.get("remote_path")
            local_path = file_record.get("local_path")
            expected_size = file_record.get("expected_size")
            if (
                not isinstance(source_path, str)
                or not source_path.startswith("/")
                or not isinstance(local_path, str)
                or not local_path.startswith("/")
                or not _valid_integer(expected_size, nonnegative=True)
            ):
                return ArrImportProof.unverified()
            try:
                observed = source_stat(source_path)
            except Exception:
                observed = None
            if (
                not isinstance(observed, Mapping)
                or observed.get("regular_file") is not True
                or observed.get("size") != expected_size
                or not _valid_integer(observed.get("mtime_ns"))
            ):
                return ArrImportProof.unverified()
            file_record["expected_mtime_ns"] = observed["mtime_ns"]
            imported_paths.append(local_path)
        return ArrImportProof.verified(imported_paths)

    return prove


def verify_local_imported_file(
    file_record: Mapping[str, Any], library_roots: Sequence[str]
) -> Mapping[str, Any] | None:
    """Read-only size/mtime observation for one path from Arr import history."""
    path = file_record.get("local_path") if isinstance(file_record, Mapping) else None
    if not isinstance(path, str) or not _path_is_within(path, library_roots):
        return None
    try:
        path_object = Path(path)
        if path_object.is_symlink():
            return None
        resolved = path_object.resolve(strict=True)
        if not _path_is_within(str(resolved), library_roots):
            return None
        observed = os.lstat(resolved)
    except OSError:
        return None
    return {
        "regular_file": stat.S_ISREG(observed.st_mode),
        "size": observed.st_size,
        "mtime_ns": observed.st_mtime_ns,
    }


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

    Runtime cleanup uses normalized remote file paths as identities and counts
    references across every Transmission torrent before allowing removal.
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


def _retention_preflight_reasons(candidate: Mapping[str, Any]) -> list[str]:
    """Reject incomplete, below-policy, or tracker-unsafe candidates before I/O."""
    decision = evaluate_retention(candidate)
    preflight_reasons = {
        "incomplete_torrent",
        "below_retention_threshold",
        "tracker_classification_unknown",
        "private_ratio_unavailable",
        "private_ratio_missing",
        "private_ratio_malformed",
        "private_ratio_below_floor",
        "payload_files_missing",
        "file_metadata_invalid",
        "file_unmapped",
        "source_mapping_unverified",
        "source_ownership_unverified",
        "source_file_shared",
    }
    return [reason for reason in decision["reasons"] if reason in preflight_reasons]


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
        elif candidate.get("arr_state_available") is not True:
            reasons = ["arr_state_unavailable"]
        elif not _has_verified_source_mapping(candidate):
            reasons = ["source_mapping_unverified"]
        elif (
            source_ownership_reason := _candidate_source_ownership_reason(
                candidate, source_identity_counts
            )
        ) is not None:
            reasons = [source_ownership_reason]
        elif any(
            isinstance(file_record, Mapping)
            and isinstance(file_record.get("local_path"), str)
            and path_counts.get(os.path.normpath(file_record["local_path"]), 0) != 1
            for file_record in candidate.get("files", [])
        ):
            reasons = ["shared_file_unsafe"]
        elif (preflight_reasons := _retention_preflight_reasons(candidate)):
            reasons = preflight_reasons
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
                        verified_file.get("shared_safe") is not False
                        and normalized_path is not None
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


def _prepare_cleanup_candidates(
    candidates: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    """Carry cross-torrent path and source collisions into per-candidate decisions."""
    path_counts = _path_counts(candidates)
    source_counts = _source_identity_counts(candidates)
    prepared: list[dict[str, Any]] = []
    for candidate in candidates:
        if not isinstance(candidate, Mapping):
            prepared.append({})
            continue
        normalized = dict(candidate)
        files = candidate.get("files")
        if isinstance(files, (list, tuple)):
            normalized_files = []
            for file_record in files:
                if not isinstance(file_record, Mapping):
                    normalized_files.append(file_record)
                    continue
                normalized_file = dict(file_record)
                path = normalized_file.get("local_path")
                if isinstance(path, str) and path and path_counts.get(os.path.normpath(path), 0) != 1:
                    normalized_file["shared_safe"] = False
                identity = normalized_file.get("source_identity")
                if isinstance(identity, str) and identity:
                    existing_owner_count = normalized_file.get("source_owner_count")
                    normalized_count = source_counts.get(identity, 0)
                    normalized_file["source_owner_count"] = max(
                        existing_owner_count
                        if _valid_integer(existing_owner_count, nonnegative=True)
                        else 0,
                        normalized_count,
                    )
                normalized_files.append(normalized_file)
            normalized["files"] = normalized_files
        prepared.append(normalized)
    return prepared


def execute_cleanup(
    stage_succeeded: bool,
    candidates: Sequence[Mapping[str, Any]],
    *,
    arr_import_prover: Callable[[Mapping[str, Any]], ArrImportProof],
    local_file_verifier: Callable[[Mapping[str, Any]], Mapping[str, Any] | None],
    transmission_rpc: Any,
    apply: bool,
    revalidate_candidate: Callable[[Mapping[str, Any]], bool] | None = None,
    allowed_torrent_ids: set[int] | frozenset[int] | None = None,
    candidate_lock: Callable[[int], Any] | None = None,
    on_candidate_result: Callable[[int, str, Sequence[str]], None] | None = None,
) -> dict[str, Any]:
    """Report or remove eligible queued torrents after per-torrent revalidation."""
    prepared = _prepare_cleanup_candidates(candidates)
    if allowed_torrent_ids is not None:
        if not isinstance(allowed_torrent_ids, (set, frozenset)) or any(
            not isinstance(torrent_id, int)
            or isinstance(torrent_id, bool)
            or torrent_id <= 0
            for torrent_id in allowed_torrent_ids
        ):
            raise ValueError("queued torrent identifiers are invalid")
        prepared = [
            candidate
            for candidate in prepared
            if candidate.get("torrent_id") in allowed_torrent_ids
        ]
    counts = {
        "candidates": len(prepared),
        "eligible": 0,
        "blocked": 0,
        "removed": 0,
    }
    reasons: dict[str, int] = {}
    mode = "apply" if apply else "report-only"

    def record_reason(reason: str) -> None:
        reasons[reason] = reasons.get(reason, 0) + 1

    for candidate in prepared:
        torrent_id = candidate.get("torrent_id")
        lock = (
            candidate_lock(torrent_id)
            if apply
            and callable(candidate_lock)
            and isinstance(torrent_id, int)
            and not isinstance(torrent_id, bool)
            and torrent_id > 0
            else nullcontext()
        )
        with ExitStack() as lock_stack:
            try:
                lock_stack.enter_context(lock)
            except BlockingIOError:
                counts["blocked"] += 1
                record_reason("torrent_operation_in_progress")
                if callable(on_candidate_result) and isinstance(torrent_id, int):
                    on_candidate_result(
                        torrent_id,
                        "deferred",
                        ["torrent_operation_in_progress"],
                    )
                continue
            report = build_cleanup_report(
                stage_succeeded,
                [candidate],
                arr_import_prover=arr_import_prover,
                local_file_verifier=local_file_verifier,
            )
            if report["eligible"] != 1:
                counts["blocked"] += 1
                blocked_reasons = sorted(report["reasons"])
                for reason, count in report["reasons"].items():
                    reasons[reason] = reasons.get(reason, 0) + count
                if apply and callable(on_candidate_result) and isinstance(torrent_id, int):
                    on_candidate_result(torrent_id, "deferred", blocked_reasons)
                continue

            if not apply:
                counts["eligible"] += 1
                continue

            if (
                not isinstance(torrent_id, int)
                or isinstance(torrent_id, bool)
                or torrent_id <= 0
                or not callable(revalidate_candidate)
            ):
                counts["blocked"] += 1
                record_reason("torrent_revalidation_unavailable")
                continue
            try:
                still_eligible = revalidate_candidate(candidate)
            except Exception:
                still_eligible = False
            if still_eligible is not True:
                counts["blocked"] += 1
                record_reason("torrent_revalidation_failed")
                if callable(on_candidate_result):
                    on_candidate_result(torrent_id, "deferred", ["torrent_revalidation_failed"])
                continue

            try:
                transmission_rpc.remove_torrent(torrent_id, delete_local_data=True)
            except Exception:
                counts["blocked"] += 1
                record_reason("transmission_remove_failed")
                if callable(on_candidate_result):
                    on_candidate_result(torrent_id, "deferred", ["transmission_remove_failed"])
                continue
            counts["eligible"] += 1
            counts["removed"] += 1
            if callable(on_candidate_result):
                on_candidate_result(torrent_id, "removed", [])

    return {
        "mode": mode,
        **counts,
        "reasons": dict(sorted(reasons.items())),
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
        "arr_state_status": "unverified",
        "tracker_ratio_state": "unverified",
        "reasons": [
            "runtime_configuration_unavailable",
            "arr_import_unverified",
            "source_ownership_unverified",
            "transmission_state_unavailable",
            "arr_state_unavailable",
            "tracker_ratio_unavailable",
        ],
    }


def _load_runtime_module(name: str, filename: str) -> Any:
    module = sys.modules.get(name)
    if module is not None:
        return module
    candidates = [Path(__file__).with_name(filename)]
    candidates.extend(
        Path(directory) / filename
        for directory in os.environ.get("PYTHONPATH", "").split(os.pathsep)
        if directory
    )
    path = next((candidate for candidate in candidates if candidate.is_file()), None)
    if path is None:
        raise RuntimeError("runtime_dependency_unavailable")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError("runtime_dependency_unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(name, None)
        raise RuntimeError("runtime_dependency_unavailable") from None
    return module


def _read_runtime_value(reader: Callable[[str], str], path: Any, reason: str) -> str:
    if not isinstance(path, str) or not path.startswith("/") or "\0" in path:
        raise RuntimeError(reason)
    try:
        return reader(path)
    except Exception:
        raise RuntimeError(reason) from None


def _probe_remote_disk_usage_from_runtime(
    secret_paths: Mapping[str, Any],
    ssh_key_path: str,
    *,
    ssh_executable: str,
    ssh_keygen_executable: str,
    ssh_port: Any = 22,
    process_runner: Callable[..., Any] = subprocess.run,
) -> dict[str, int] | None:
    """Read account-level disk usage over the existing strict SSH credentials."""
    try:
        staging = _load_runtime_module(
            "ultra_media_download_stage", "ultra-media-download-stage.py"
        )
        host = _read_runtime_value(
            staging._read_secret_file, secret_paths["ssh_host"], "ssh_config_missing"
        )
        username = _read_runtime_value(
            staging._read_secret_file,
            secret_paths["ssh_username"],
            "ssh_config_missing",
        )
        known_hosts = _read_runtime_value(
            staging._read_known_hosts_file,
            secret_paths["known_hosts"],
            "ssh_config_missing",
        )
        port = staging.normalize_ssh_port(ssh_port)
    except Exception:
        return None
    if (
        not host
        or any(character.isspace() or character in "\0@:" for character in host)
        or not username
        or any(character.isspace() or character in "\0@:" for character in username)
        or not isinstance(ssh_key_path, str)
        or not Path(ssh_key_path).is_file()
    ):
        return None

    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as known_hosts_file:
            os.chmod(known_hosts_file.name, 0o600)
            known_hosts_file.write(known_hosts + "\n")
            known_hosts_file.flush()
            alias = host if port == 22 else f"[{host}]:{port}"
            key_check = process_runner(
                [
                    ssh_keygen_executable,
                    "-F",
                    alias,
                    "-f",
                    known_hosts_file.name,
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            if key_check.returncode != 0:
                return None
            ssh_arguments = [
                ssh_executable,
                "-i",
                ssh_key_path,
                "-p",
                str(port),
                "-o",
                "BatchMode=yes",
                "-o",
                "IdentitiesOnly=yes",
                "-o",
                "StrictHostKeyChecking=yes",
                "-o",
                f"UserKnownHostsFile={known_hosts_file.name}",
                "-o",
                "GlobalKnownHostsFile=/dev/null",
                "-o",
                "ConnectTimeout=15",
            ]
            probe = make_remote_disk_usage_probe(
                ssh_arguments,
                username,
                host,
                process_runner=process_runner,
            )
            return probe()
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def _read_arr_config(path: str) -> dict[str, Any]:
    try:
        config = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise RuntimeError("runtime_configuration_unavailable") from None
    if not isinstance(config, dict):
        raise RuntimeError("runtime_configuration_unavailable")
    roots = config.get("libraryRoots")
    apis = config.get("arrApis")
    if (
        not isinstance(roots, list)
        or not roots
        or any(not isinstance(root, str) or not root.startswith("/") or "\0" in root for root in roots)
        or not isinstance(apis, list)
        or not apis
    ):
        raise RuntimeError("runtime_configuration_unavailable")
    return config


def ack_stale_receipt_if_unlocked(
    staging: Any,
    queue_root: str | Path,
    runtime_root: str | Path,
    receipt: Mapping[str, Any],
) -> bool:
    """Acknowledge stale work only if staging is not concurrently updating it."""
    torrent_id = receipt.get("torrent_id")
    if not isinstance(torrent_id, int) or isinstance(torrent_id, bool) or torrent_id <= 0:
        return False
    try:
        with staging.torrent_operation_lock(runtime_root, torrent_id, blocking=False):
            return staging.ack_staged_torrent_receipt(queue_root, receipt)
    except BlockingIOError:
        return False


def match_staged_torrent_receipts(
    receipts: Sequence[Mapping[str, Any]],
    torrents: Sequence[Mapping[str, Any]],
    *,
    fingerprint_fn: Callable[[Mapping[str, Any]], str],
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    """Match private staging receipts to the current RPC snapshot without logging identities."""
    current: dict[int, str | None] = {}
    for torrent in torrents:
        torrent_id = torrent.get("id") if isinstance(torrent, Mapping) else None
        if not isinstance(torrent_id, int) or isinstance(torrent_id, bool) or torrent_id <= 0:
            continue
        try:
            fingerprint = fingerprint_fn(torrent)
        except Exception:
            fingerprint = None
        current[torrent_id] = fingerprint

    matched = []
    counts = {"matched": 0, "stale": 0, "missing": 0}
    for receipt in receipts:
        torrent_id = receipt.get("torrent_id") if isinstance(receipt, Mapping) else None
        fingerprint = receipt.get("fingerprint") if isinstance(receipt, Mapping) else None
        if not isinstance(torrent_id, int) or isinstance(torrent_id, bool) or torrent_id <= 0 or not isinstance(fingerprint, str):
            counts["stale"] += 1
            continue
        if torrent_id not in current:
            counts["missing"] += 1
            continue
        if current[torrent_id] != fingerprint:
            counts["stale"] += 1
            continue
        matched.append(dict(receipt))
        counts["matched"] += 1
    return matched, counts


def _queue_has_receipt_files(queue_root: str | Path) -> bool:
    root = Path(queue_root)
    if root.is_symlink():
        raise RuntimeError("runtime_configuration_unavailable")
    if not root.exists():
        return False
    if not root.is_dir():
        raise RuntimeError("runtime_configuration_unavailable")
    try:
        with os.scandir(root) as entries:
            return any(
                entry.name.endswith(".json") and entry.is_file(follow_symlinks=False)
                for entry in entries
            )
    except OSError:
        raise RuntimeError("runtime_configuration_unavailable") from None


def run_runtime_cleanup(
    secret_paths: Mapping[str, str],
    ssh_key_path: str,
    arr_config_path: str,
    *,
    ssh_executable: str,
    ssh_keygen_executable: str,
    ssh_port: Any = 22,
    apply: bool,
    private_tracker_ratio_protection: bool = False,
    staging_root: str = STAGING_ROOT,
    queue_root: str = CLEANUP_QUEUE_ROOT,
    runtime_root: str = RUNTIME_ROOT,
    process_runner: Callable[..., Any] = subprocess.run,
    now_ns: int | None = None,
) -> dict[str, Any]:
    """Read live state, prove staged Arr imports, and optionally clean the seedbox."""
    if type(private_tracker_ratio_protection) is not bool:
        raise RuntimeError("runtime_configuration_unavailable")
    if now_ns is None:
        now_ns = time.time_ns()
    if not isinstance(now_ns, int) or isinstance(now_ns, bool) or now_ns <= 0:
        raise RuntimeError("runtime_configuration_unavailable")
    if apply and not _queue_has_receipt_files(queue_root):
        return {
            "mode": "apply",
            "candidates": 0,
            "eligible": 0,
            "blocked": 0,
            "removed": 0,
            "queued": 0,
            "stale_or_missing": 0,
            "reasons": {},
        }
    staging = _load_runtime_module("ultra_media_download_stage", "ultra-media-download-stage.py")
    transmission_module = _load_runtime_module("transmission_rpc", "transmission_rpc.py")
    pending_receipts = (
        staging.read_pending_torrent_receipts(queue_root, now_ns=now_ns)
        if apply
        else []
    )
    if apply and not pending_receipts:
        return {
            "mode": "apply",
            "candidates": 0,
            "eligible": 0,
            "blocked": 0,
            "removed": 0,
            "queued": 0,
            "stale_or_missing": 0,
            "reasons": {},
        }
    queued_count = len(pending_receipts)
    try:
        rpc_url = _read_runtime_value(staging._read_secret_file, secret_paths["rpc_url"], "rpc_url_missing")
        download_root = _read_runtime_value(staging._read_secret_file, secret_paths["download_root"], "download_root_missing")
        ssh_host = _read_runtime_value(staging._read_secret_file, secret_paths["ssh_host"], "ssh_config_missing")
        ssh_username = _read_runtime_value(staging._read_secret_file, secret_paths["ssh_username"], "ssh_config_missing")
        known_hosts = _read_runtime_value(staging._read_known_hosts_file, secret_paths["known_hosts"], "ssh_config_missing")
        rpc_username = _read_runtime_value(staging._read_secret_file, secret_paths["rpc_username"], "rpc_username_missing")
        rpc_password = _read_runtime_value(staging._read_secret_file, secret_paths["rpc_password"], "rpc_password_missing")
    except (KeyError, TypeError):
        raise RuntimeError("runtime_configuration_unavailable") from None

    try:
        rpc_url, mappings = staging.validate_staging_config(
            rpc_url, download_root, rpc_username, rpc_password
        )
        port = staging.normalize_ssh_port(ssh_port)
    except Exception:
        raise RuntimeError("runtime_configuration_unavailable") from None
    if (
        not ssh_host
        or any(character.isspace() or character in "\0@:" for character in ssh_host)
        or not ssh_username
        or any(character.isspace() or character in "\0@:" for character in ssh_username)
        or not Path(ssh_key_path).is_file()
    ):
        raise RuntimeError("ssh_config_missing")

    arr_config = _read_arr_config(arr_config_path)
    library_roots = arr_config["libraryRoots"]
    try:
        imported_paths = fetch_arr_import_paths(arr_config["arrApis"], library_roots)
    except Exception:
        raise RuntimeError("arr_state_unavailable") from None

    tracker_classifier = None
    if not private_tracker_ratio_protection:
        # User-confirmed current state: no private-account trackers. Keep the
        # classifier extension opt-in; enabling it makes unknown trackers fail closed.
        tracker_classifier = lambda _host: "public"
    try:
        rpc = transmission_module.TransmissionRPC(
            rpc_url,
            rpc_username,
            rpc_password,
            tracker_classifier=tracker_classifier,
        )
        torrents = rpc.get_torrents()
    except Exception:
        raise RuntimeError("transmission_state_unavailable") from None

    matched_receipts, receipt_counts = match_staged_torrent_receipts(
        pending_receipts,
        torrents,
        fingerprint_fn=lambda torrent: staging.fingerprint_torrent(torrent, mappings),
    )
    matched_keys = {
        (receipt["torrent_id"], receipt["fingerprint"])
        for receipt in matched_receipts
    }
    stale_or_missing = receipt_counts["stale"] + receipt_counts["missing"]
    for receipt in pending_receipts:
        key = (receipt["torrent_id"], receipt["fingerprint"])
        if key in matched_keys:
            continue
        ack_stale_receipt_if_unlocked(
            staging, queue_root, runtime_root, receipt
        )

    if not matched_receipts:
        return {
            "mode": "apply",
            "candidates": 0,
            "eligible": 0,
            "blocked": 0,
            "removed": 0,
            "queued": queued_count,
            "stale_or_missing": stale_or_missing,
            "reasons": {},
        }
    receipts_by_id = {receipt["torrent_id"]: receipt for receipt in matched_receipts}
    allowed_torrent_ids = set(receipts_by_id)

    candidates = build_cleanup_candidates(
        torrents,
        mappings,
        imported_paths,
        staging_root=staging_root,
        path_mapper=staging.map_remote_path_to_staging,
    )
    ssh_port_value = str(port)

    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as known_hosts_file:
        os.chmod(known_hosts_file.name, 0o600)
        known_hosts_file.write(known_hosts + "\n")
        known_hosts_file.flush()
        known_hosts_alias = ssh_host if port == 22 else f"[{ssh_host}]:{port}"
        key_check = process_runner(
            [ssh_keygen_executable, "-F", known_hosts_alias, "-f", known_hosts_file.name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if key_check.returncode != 0:
            raise RuntimeError("ssh_host_key_unavailable")
        ssh_arguments = [
            ssh_executable,
            "-i",
            ssh_key_path,
            "-p",
            ssh_port_value,
            "-o",
            "BatchMode=yes",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            f"UserKnownHostsFile={known_hosts_file.name}",
            "-o",
            "GlobalKnownHostsFile=/dev/null",
            "-o",
            "ConnectTimeout=15",
        ]
        source_stat = make_remote_source_stat(
            ssh_arguments,
            ssh_username,
            ssh_host,
            process_runner=process_runner,
        )
        arr_import_prover = make_arr_import_prover(source_stat)
        local_file_verifier = lambda file_record: verify_local_imported_file(
            file_record, library_roots
        )

        def revalidate_candidate(previous: Mapping[str, Any]) -> bool:
            torrent_id = previous.get("torrent_id")
            expected_receipt = receipts_by_id.get(torrent_id)
            current_receipts = staging.read_pending_torrent_receipts(
                queue_root, now_ns=2**63 - 1
            )
            current_receipt = next(
                (receipt for receipt in current_receipts if receipt.get("torrent_id") == torrent_id),
                None,
            )
            if (
                expected_receipt is None
                or current_receipt is None
                or current_receipt.get("fingerprint") != expected_receipt.get("fingerprint")
                or current_receipt.get("receipt_id") != expected_receipt.get("receipt_id")
            ):
                return False
            fresh_torrents = rpc.get_torrents()
            fresh_source = next(
                (torrent for torrent in fresh_torrents if torrent.get("id") == torrent_id),
                None,
            )
            if (
                fresh_source is None
                or staging.fingerprint_torrent(fresh_source, mappings)
                != expected_receipt.get("fingerprint")
            ):
                return False
            fresh_imported_paths = fetch_arr_import_paths(arr_config["arrApis"], library_roots)
            fresh_candidates = build_cleanup_candidates(
                fresh_torrents,
                mappings,
                fresh_imported_paths,
                staging_root=staging_root,
                path_mapper=staging.map_remote_path_to_staging,
            )
            prepared_fresh_candidates = _prepare_cleanup_candidates(fresh_candidates)
            torrent_id = previous.get("torrent_id")
            current = next(
                (item for item in prepared_fresh_candidates if item.get("torrent_id") == torrent_id),
                None,
            )
            if (
                current is None
                or current.get("remote_download_directory") != previous.get("remote_download_directory")
                or current.get("remote_file_paths") != previous.get("remote_file_paths")
            ):
                return False
            report = build_cleanup_report(
                True,
                [current],
                arr_import_prover=arr_import_prover,
                local_file_verifier=local_file_verifier,
            )
            return report["eligible"] == 1

        def record_queue_result(
            torrent_id: int,
            status: str,
            reasons: Sequence[str],
        ) -> None:
            receipt = receipts_by_id.get(torrent_id)
            if receipt is None:
                return
            if status == "removed":
                staging.ack_staged_torrent_receipt(queue_root, receipt)
            elif status == "deferred":
                reason = next(iter(reasons), "runtime_cleanup_failed")
                staging.defer_staged_torrent_receipt(
                    queue_root,
                    receipt,
                    now_ns=now_ns,
                    reason=reason,
                )

        report = execute_cleanup(
            True,
            candidates,
            arr_import_prover=arr_import_prover,
            local_file_verifier=local_file_verifier,
            transmission_rpc=rpc,
            apply=apply,
            revalidate_candidate=revalidate_candidate if apply else None,
            allowed_torrent_ids=allowed_torrent_ids,
            candidate_lock=lambda torrent_id: staging.torrent_operation_lock(
                runtime_root, torrent_id, blocking=False
            ),
            on_candidate_result=record_queue_result,
        )
        report["queued"] = queued_count
        report["stale_or_missing"] = stale_or_missing
        report["pending_after_run"] = len(
            staging.read_pending_torrent_receipts(
                queue_root, now_ns=2**63 - 1
            )
        )
        return report


def _collect_remote_disk_usage(args: argparse.Namespace) -> dict[str, Any]:
    disk_usage = _probe_remote_disk_usage_from_runtime(
        {
            "ssh_host": args.ssh_host,
            "ssh_username": args.ssh_username,
            "known_hosts": args.known_hosts,
        },
        args.ssh_key,
        ssh_executable=args.ssh,
        ssh_keygen_executable=args.ssh_keygen,
        ssh_port=args.ssh_port,
    )
    sample_timestamp = int(time.time())
    try:
        write_remote_disk_metrics(
            args.remote_disk_metrics_path,
            used_bytes=(disk_usage["used_bytes"] if disk_usage is not None else None),
            capacity_bytes=args.remote_disk_capacity_bytes,
            warning_threshold_bytes=args.remote_disk_warning_threshold_bytes,
            sample_timestamp_seconds=sample_timestamp,
        )
    except (OSError, ValueError):
        print(
            json.dumps(
                {"event": "remote_disk_metrics_write_failed"},
                sort_keys=True,
                separators=(",", ":"),
            ),
            flush=True,
        )
    if disk_usage is None:
        return {
            "event": "remote_disk_usage_unavailable",
            "remote_disk_probe_success": False,
            "sample_timestamp_seconds": sample_timestamp,
        }
    used_bytes = disk_usage["used_bytes"]
    return {
        "event": "remote_disk_usage",
        "remote_disk_used_bytes": used_bytes,
        "remote_disk_capacity_bytes": args.remote_disk_capacity_bytes,
        "remote_disk_warning_threshold_bytes": args.remote_disk_warning_threshold_bytes,
        "remote_disk_used_percent": round(
            100 * used_bytes / args.remote_disk_capacity_bytes, 2
        ),
        "remote_disk_probe_success": True,
        "sample_timestamp_seconds": sample_timestamp,
    }


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report-only", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--queue-root", default=CLEANUP_QUEUE_ROOT)
    parser.add_argument("--rpc-url")
    parser.add_argument("--download-root")
    parser.add_argument("--ssh-host")
    parser.add_argument("--ssh-username")
    parser.add_argument("--ssh-port", type=int, default=22)
    parser.add_argument("--known-hosts")
    parser.add_argument("--ssh-key")
    parser.add_argument("--rpc-username")
    parser.add_argument("--rpc-password")
    parser.add_argument("--ssh")
    parser.add_argument("--ssh-keygen")
    parser.add_argument("--arr-config")
    parser.add_argument("--remote-disk-capacity-bytes", type=int, default=REMOTE_DISK_CAPACITY_BYTES)
    parser.add_argument(
        "--remote-disk-warning-threshold-bytes",
        type=int,
        default=REMOTE_DISK_WARNING_THRESHOLD_BYTES,
    )
    parser.add_argument("--remote-disk-metrics-path", default=REMOTE_DISK_METRICS_PATH)
    parser.add_argument("--remote-disk-monitoring", action="store_true")
    parser.add_argument("--private-tracker-ratio-protection", action="store_true")
    args = parser.parse_args(argv)
    if args.apply and args.report_only:
        print("cleanup failed reason=mode_conflict")
        return 2
    try:
        if args.apply:
            required_paths = (
                args.rpc_url,
                args.download_root,
                args.ssh_host,
                args.ssh_username,
                args.known_hosts,
                args.ssh_key,
                args.rpc_username,
                args.rpc_password,
                args.ssh,
                args.ssh_keygen,
                args.arr_config,
            )
            if any(not value for value in required_paths):
                raise RuntimeError("runtime_configuration_unavailable")
            if args.remote_disk_monitoring:
                if (
                    args.remote_disk_capacity_bytes <= 0
                    or args.remote_disk_warning_threshold_bytes <= 0
                    or args.remote_disk_warning_threshold_bytes > args.remote_disk_capacity_bytes
                ):
                    raise RuntimeError("runtime_configuration_unavailable")
                print(
                    json.dumps(
                        _collect_remote_disk_usage(args),
                        sort_keys=True,
                        separators=(",", ":"),
                    ),
                    flush=True,
                )
            report = run_runtime_cleanup(
                {
                    "rpc_url": args.rpc_url,
                    "download_root": args.download_root,
                    "ssh_host": args.ssh_host,
                    "ssh_username": args.ssh_username,
                    "known_hosts": args.known_hosts,
                    "rpc_username": args.rpc_username,
                    "rpc_password": args.rpc_password,
                },
                args.ssh_key,
                args.arr_config,
                ssh_executable=args.ssh,
                ssh_keygen_executable=args.ssh_keygen,
                ssh_port=args.ssh_port,
                apply=True,
                private_tracker_ratio_protection=args.private_tracker_ratio_protection,
                queue_root=args.queue_root,
            )
        else:
            report = _runtime_unverified_report()
    except OSError:
        print("cleanup failed reason=local_io_failure")
        return 1
    except Exception as error:
        reason = str(error)
        safe_reasons = {
            "arr_state_unavailable",
            "download_root_malformed",
            "download_root_missing",
            "rpc_password_missing",
            "rpc_url_insecure",
            "rpc_url_malformed",
            "rpc_url_missing",
            "rpc_username_missing",
            "runtime_configuration_unavailable",
            "runtime_dependency_unavailable",
            "ssh_config_missing",
            "ssh_host_key_unavailable",
            "transmission_state_unavailable",
        }
        print(f"cleanup failed reason={reason if reason in safe_reasons else 'runtime_cleanup_failed'}")
        return 1
    if args.apply and report.get("queued", 0) == 0:
        return 0
    print(
        json.dumps(
            {"event": "cleanup_queue_summary", **report},
            sort_keys=True,
            separators=(",", ":"),
        ),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
