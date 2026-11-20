"""Copy completed Transmission payloads into Drlight's non-library stage.

The only remote operations are Transmission's session-get/torrent-get and
read-only rsync copies. Runtime configuration and logs deliberately exclude
per-torrent and remote-path details.
"""

import argparse
import fcntl
import hashlib
import ipaddress
import json
import math
import os
import posixpath
import re
import secrets
import selectors
import shlex
import stat
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager, nullcontext
from pathlib import Path
from typing import Any, Callable, Iterator, Mapping, Sequence
from urllib.parse import urlsplit

from ultra_media_file_stat import make_remote_source_stat


STAGING_ROOT = "/srv/media/.arr-staging"
RUNTIME_ROOT = "/run/ultra-media"
CLEANUP_QUEUE_ROOT = "/var/lib/ultra-media/cleanup-queue"


class StagingConfigurationError(ValueError):
    """A safe configuration or path error carrying only a reason code."""

    def __init__(self, reason: str = "malformed_path") -> None:
        self.reason = reason
        super().__init__(reason)


def _normalize_absolute_remote_path(value: Any) -> str:
    if not isinstance(value, str) or not value.startswith("/") or "\0" in value:
        raise StagingConfigurationError("malformed_path")
    if ".." in value.split("/"):
        raise StagingConfigurationError("malformed_path")
    return posixpath.normpath(value)


def _normalize_relative_path(value: Any, reason: str = "malformed_path") -> str:
    if not isinstance(value, str) or not value or value.startswith("/") or "\0" in value:
        raise StagingConfigurationError(reason)
    if ".." in value.split("/"):
        raise StagingConfigurationError(reason)
    normalized = posixpath.normpath(value)
    if normalized in ("", ".") or normalized.startswith("../"):
        raise StagingConfigurationError(reason)
    return normalized


def normalize_download_root(download_root: Any) -> list[dict[str, str]]:
    """Validate one configured remote root and preserve its relative layout."""
    remote_root = _normalize_absolute_remote_path(download_root)
    if remote_root == "/":
        raise StagingConfigurationError("malformed_path")
    return [{"remoteRoot": remote_root, "stagingSubpath": ""}]


def _validate_normalized_mappings(mappings: Any) -> list[dict[str, str]]:
    if not isinstance(mappings, list) or not mappings:
        raise StagingConfigurationError("download_mappings_missing")
    normalized: list[dict[str, str]] = []
    seen_roots: set[str] = set()
    seen_staging_roots: set[str] = set()
    for mapping in mappings:
        if not isinstance(mapping, Mapping):
            raise StagingConfigurationError("download_mapping_malformed")
        remote_root = _normalize_absolute_remote_path(mapping.get("remoteRoot"))
        raw_staging_subpath = mapping.get("stagingSubpath")
        staging_subpath = (
            ""
            if raw_staging_subpath == ""
            else _normalize_relative_path(
                raw_staging_subpath, "download_mapping_malformed"
            )
        )
        if remote_root in seen_roots or staging_subpath in seen_staging_roots:
            raise StagingConfigurationError("download_mapping_ambiguous")
        seen_roots.add(remote_root)
        seen_staging_roots.add(staging_subpath)
        normalized.append(
            {"remoteRoot": remote_root, "stagingSubpath": staging_subpath}
        )
    return normalized


def _is_valid_rpc_hostname(hostname: str) -> bool:
    try:
        ipaddress.ip_address(hostname)
        return True
    except ValueError:
        pass

    try:
        ascii_hostname = hostname.encode("idna").decode("ascii")
    except UnicodeError:
        return False

    if ascii_hostname.endswith("."):
        ascii_hostname = ascii_hostname[:-1]
    if not ascii_hostname or len(ascii_hostname) > 253:
        return False

    labels = ascii_hostname.split(".")
    return all(
        label
        and len(label) <= 63
        and label[0].isalnum()
        and label[-1].isalnum()
        and all(character.isalnum() or character == "-" for character in label)
        for label in labels
    )


def normalize_ssh_port(value: Any = 22) -> int:
    """Validate an explicit port or use the non-secret SSH default."""
    if value is None:
        value = 22
    if isinstance(value, bool) or not isinstance(value, (str, int)) or not str(value).isdigit():
        raise StagingConfigurationError("ssh_config_missing")
    port = int(value)
    if not 1 <= port <= 65535:
        raise StagingConfigurationError("ssh_config_missing")
    return port


def validate_staging_config(
    rpc_url: Any,
    download_root: Any,
    rpc_username: Any,
    rpc_password: Any,
) -> tuple[str, list[dict[str, str]]]:
    """Fail closed on absent/malformed scalar settings before RPC or rsync."""
    if not isinstance(rpc_url, str) or not rpc_url or any(c in rpc_url for c in "\r\n\0"):
        raise StagingConfigurationError("rpc_url_missing")
    try:
        parsed_url = urlsplit(rpc_url)
        if parsed_url.scheme != "https":
            raise StagingConfigurationError("rpc_url_insecure")
        port = parsed_url.port
        valid_url = (
            bool(parsed_url.hostname)
            and _is_valid_rpc_hostname(parsed_url.hostname)
            and parsed_url.username is None
            and parsed_url.password is None
            and not any(character.isspace() for character in rpc_url)
            and (port is None or 1 <= port <= 65535)
        )
    except StagingConfigurationError:
        raise
    except ValueError:
        valid_url = False
    if not valid_url:
        raise StagingConfigurationError("rpc_url_malformed")

    if (
        not isinstance(rpc_username, str)
        or not rpc_username.strip()
        or any(c in rpc_username for c in "\r\n\0")
    ):
        raise StagingConfigurationError("rpc_username_missing")
    if (
        not isinstance(rpc_password, str)
        or not rpc_password.strip()
        or any(c in rpc_password for c in "\r\n\0")
    ):
        raise StagingConfigurationError("rpc_password_missing")

    try:
        mappings = normalize_download_root(download_root)
    except StagingConfigurationError:
        raise StagingConfigurationError("download_root_malformed") from None
    return rpc_url, mappings


def map_remote_path_to_staging(
    download_directory: Any,
    file_path: Any,
    mappings: Any,
    staging_root: str = STAGING_ROOT,
) -> str:
    """Map a Transmission payload file to its exact normalized stage path."""
    remote_directory = _normalize_absolute_remote_path(download_directory)
    relative_file = _normalize_relative_path(file_path)
    remote_path = posixpath.normpath(posixpath.join(remote_directory, relative_file))
    if posixpath.commonpath((remote_directory, remote_path)) != remote_directory:
        raise StagingConfigurationError("malformed_path")

    normalized_mappings = _validate_normalized_mappings(mappings)
    matches: list[tuple[int, dict[str, str], str]] = []
    for mapping in normalized_mappings:
        remote_root = mapping["remoteRoot"]
        if remote_root == "/":
            is_match = remote_path.startswith("/")
            suffix = remote_path.lstrip("/")
        else:
            is_match = remote_path == remote_root or remote_path.startswith(remote_root + "/")
            suffix = remote_path[len(remote_root) :].lstrip("/") if is_match else ""
        if is_match:
            matches.append((len(remote_root), mapping, suffix))
    if not matches:
        raise StagingConfigurationError("unknown_path")
    if len(matches) != 1:
        raise StagingConfigurationError("download_mapping_ambiguous")

    _, mapping, suffix = matches[0]
    local_root = Path(staging_root).resolve()
    target = local_root / mapping["stagingSubpath"]
    if suffix:
        target /= _normalize_relative_path(suffix)
    normalized_target = Path(os.path.normpath(str(target)))
    if os.path.commonpath((str(local_root), str(normalized_target))) != str(local_root):
        raise StagingConfigurationError("malformed_path")
    return str(normalized_target)


def normalize_transmission_source_mappings(
    torrent: Any,
    mappings: Any,
    *,
    staging_root: str = STAGING_ROOT,
) -> dict[str, Any]:
    """Attach source-mapping proof without retaining or logging source paths.

    A file is marked mapped only when its Transmission-reported download
    directory and file name match exactly one normalized runtime mapping.
    Missing or malformed RPC path data and any mapping error leave both facts
    false.
    """
    candidate_value = torrent.get("candidate") if isinstance(torrent, Mapping) else None
    candidate = dict(candidate_value) if isinstance(candidate_value, Mapping) else {}
    existing_files = candidate.get("files")
    existing_files = existing_files if isinstance(existing_files, list) else []
    file_paths = torrent.get("file_paths") if isinstance(torrent, Mapping) else None
    file_paths = file_paths if isinstance(file_paths, list) else []
    file_count = max(len(file_paths), len(existing_files))
    paths_valid = (
        isinstance(torrent, Mapping)
        and torrent.get("file_paths_valid") is True
        and bool(file_paths)
        and isinstance(torrent.get("download_directory"), str)
    )

    normalized_files = []
    for index in range(file_count):
        existing_file = existing_files[index] if index < len(existing_files) else None
        file_record = dict(existing_file) if isinstance(existing_file, Mapping) else {}
        verified = False
        if paths_valid and index < len(file_paths):
            try:
                map_remote_path_to_staging(
                    torrent.get("download_directory"),
                    file_paths[index],
                    mappings,
                    staging_root=staging_root,
                )
            except StagingConfigurationError:
                pass
            else:
                verified = True
        file_record["mapped"] = verified
        file_record["source_mapping_verified"] = verified
        # Source path mapping does not prove inode/ownership uniqueness. A
        # separate read-only source inventory must establish these facts before
        # cleanup can consider the torrent eligible.
        file_record["source_identity"] = None
        file_record["source_ownership_verified"] = False
        file_record["source_owner_count"] = None
        file_record.setdefault("local_match", False)
        file_record.setdefault("shared_safe", False)
        normalized_files.append(file_record)

    candidate["files"] = normalized_files
    return candidate


def build_rsync_arguments(
    rsync_executable: str,
    ssh_command: str,
    remote_source: str,
    local_destination: str,
) -> list[str]:
    """Build one non-destructive, path-preserving rsync file copy."""
    return [
        rsync_executable,
        "--recursive",
        "--times",
        "--omit-dir-times",
        "--no-perms",
        "--chmod=Du=rwx,Dg=rwx,Do=rx,Fu=rw,Fg=rw,Fo=r,ugo-s,o-t",
        "--protect-args",
        "--bwlimit=20000",
        "--partial-dir=.rsync-partial",
        "--info=progress2",
        f"--rsh={ssh_command}",
        remote_source,
        local_destination,
    ]


_RSYNC_PROGRESS_PATTERN = re.compile(r"^\s*([\d,]+)\s+\d+%")


def parse_rsync_progress_bytes(output: bytes | str) -> int | None:
    """Return the last aggregate byte count from rsync progress output only."""
    if isinstance(output, bytes):
        text = output.decode("ascii", errors="ignore")
    elif isinstance(output, str):
        text = output
    else:
        return None
    latest = None
    for record in re.split(r"[\r\n]+", text):
        match = _RSYNC_PROGRESS_PATTERN.match(record)
        if match is None:
            continue
        try:
            latest = int(match.group(1).replace(",", ""))
        except ValueError:
            continue
    return latest


def run_rsync_with_progress(
    arguments: Sequence[str],
    on_progress: Callable[[int], None],
    *,
    process_factory: Callable[..., Any] = subprocess.Popen,
    poll_interval: float = 1.0,
) -> None:
    """Run rsync while extracting only numeric progress, never diagnostic text."""
    process = process_factory(
        list(arguments),
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        bufsize=0,
    )
    if process.stdout is None:
        raise OSError("rsync progress stream is unavailable")
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    buffered = b""
    latest_progress = 0

    def report_progress(value: int) -> None:
        on_progress(value)

    try:
        while selector.get_map():
            events = selector.select(poll_interval)
            if not events:
                if process.poll() is not None:
                    break
                report_progress(latest_progress)
                continue
            for key, _mask in events:
                chunk = os.read(key.fileobj.fileno(), 4096)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                records = re.split(br"[\r\n]+", buffered + chunk)
                buffered = records.pop()
                for record in records:
                    progress = parse_rsync_progress_bytes(record)
                    if progress is not None:
                        latest_progress = max(latest_progress, progress)
                        report_progress(latest_progress)
            if process.poll() is None:
                report_progress(latest_progress)
        trailing_progress = parse_rsync_progress_bytes(buffered)
        if trailing_progress is not None:
            report_progress(trailing_progress)
        returncode = process.wait()
        if returncode != 0:
            raise subprocess.CalledProcessError(returncode, list(arguments))
    except BaseException:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        raise
    finally:
        selector.close()
        process.stdout.close()


def build_staging_plan(
    torrents: Sequence[Mapping[str, Any]],
    mappings: Any,
    *,
    staging_root: str | Path = STAGING_ROOT,
) -> dict[str, Any]:
    """Plan only complete torrents whose every payload path maps safely."""
    normalized_mappings = _validate_normalized_mappings(mappings)
    planned_torrents: list[dict[str, Any]] = []
    completed_candidates = 0
    skipped_incomplete = 0
    skipped_unknown_path = 0
    skipped_malformed_path = 0
    skipped_unknown_completion_time = 0
    planned_files = 0
    known_bytes = 0
    unknown_size_files = 0

    for torrent in torrents:
        candidate = normalize_transmission_source_mappings(
            torrent, normalized_mappings, staging_root=str(staging_root)
        )
        if candidate.get("complete") is not True:
            skipped_incomplete += 1
            continue
        completed_candidates += 1

        torrent_id = torrent.get("id") if isinstance(torrent, Mapping) else None
        paths = torrent.get("file_paths") if isinstance(torrent, Mapping) else None
        download_directory = torrent.get("download_directory") if isinstance(torrent, Mapping) else None
        source_files = candidate.get("files")
        if (
            not isinstance(torrent_id, int)
            or isinstance(torrent_id, bool)
            or torrent_id <= 0
            or torrent.get("file_paths_valid") is not True
            or not isinstance(paths, list)
            or not paths
            or not isinstance(download_directory, str)
            or not isinstance(source_files, list)
            or len(source_files) != len(paths)
        ):
            skipped_malformed_path += 1
            continue

        file_sizes = torrent.get("file_sizes")
        sizes_valid = (
            torrent.get("file_sizes_valid") is True
            and isinstance(file_sizes, list)
            and len(file_sizes) == len(paths)
        )
        transfers = []
        destinations: set[str] = set()
        reason: str | None = None
        for index, file_path in enumerate(paths):
            try:
                normalized_directory = _normalize_absolute_remote_path(download_directory)
                normalized_file = _normalize_relative_path(file_path)
                remote_source = posixpath.normpath(
                    posixpath.join(normalized_directory, normalized_file)
                )
                local_destination = map_remote_path_to_staging(
                    download_directory,
                    file_path,
                    normalized_mappings,
                    staging_root=str(staging_root),
                )
            except StagingConfigurationError as error:
                reason = error.reason
                break
            if source_files[index].get("source_mapping_verified") is not True:
                reason = "malformed_path"
                break
            if local_destination in destinations:
                reason = "malformed_path"
                break
            destinations.add(local_destination)
            size = file_sizes[index] if sizes_valid else None
            if not isinstance(size, int) or isinstance(size, bool) or size < 0:
                size = None
            transfers.append(
                {
                    "remote_source": remote_source,
                    "local_destination": local_destination,
                    "size_bytes": size,
                }
            )

        if reason == "unknown_path":
            skipped_unknown_path += 1
            continue
        if reason is not None or not transfers:
            skipped_malformed_path += 1
            continue

        done_date = torrent.get("done_date")
        if (
            not isinstance(done_date, int)
            or isinstance(done_date, bool)
            or done_date <= 0
        ):
            skipped_unknown_completion_time += 1
            continue

        planned_torrents.append(
            {
                "torrent_id": torrent_id,
                "done_date": done_date,
                "fingerprint": fingerprint_torrent(torrent, normalized_mappings),
                "transfers": transfers,
                "torrent": torrent,
            }
        )
        planned_files += len(transfers)
        for transfer in transfers:
            size = transfer["size_bytes"]
            if size is None:
                unknown_size_files += 1
            else:
                known_bytes += size

    planned_torrents.sort(key=lambda item: item["done_date"])

    return {
        "torrents": planned_torrents,
        "totals": {
            "torrents": len(planned_torrents),
            "files": planned_files,
            "bytes": known_bytes if unknown_size_files == 0 else None,
            "unknown_size_files": unknown_size_files,
        },
        "counts": {
            "completed_candidates": completed_candidates,
            "skipped_incomplete": skipped_incomplete,
            "skipped_unknown_path": skipped_unknown_path,
            "skipped_malformed_path": skipped_malformed_path,
            "skipped_unknown_completion_time": skipped_unknown_completion_time,
        },
    }


class StageProgressReporter:
    """Emit privacy-safe aggregate progress events at a bounded cadence."""

    def __init__(
        self,
        totals: Mapping[str, Any],
        *,
        emit: Callable[[Mapping[str, Any]], None] | None = None,
        clock: Callable[[], float] = time.monotonic,
        wall_clock: Callable[[], float] = time.time,
        completion_times: Sequence[int] = (),
        unorderable_completed_torrents: int = 0,
        interval_seconds: int = 60,
    ) -> None:
        if isinstance(interval_seconds, bool) or not isinstance(interval_seconds, int) or interval_seconds <= 0:
            raise ValueError("progress interval must be a positive integer")
        self.totals = dict(totals)
        self.clock = clock
        self.wall_clock = wall_clock
        self.interval_seconds = interval_seconds
        self.emit_event = emit or self._emit_json
        self.started_at = clock()
        self.last_emit_at: float | None = None
        self.last_emit_bytes = 0
        self.bytes_per_second: float | None = None
        self.completion_times: tuple[int, ...] = ()
        self.unorderable_completed_torrents = 0
        self.set_completion_context(
            completion_times, unorderable_completed_torrents
        )

    def set_completion_context(
        self,
        completion_times: Sequence[int],
        unorderable_completed_torrents: int,
    ) -> None:
        if (
            not isinstance(completion_times, Sequence)
            or isinstance(completion_times, (str, bytes))
            or any(
                not isinstance(timestamp, int)
                or isinstance(timestamp, bool)
                or timestamp <= 0
                for timestamp in completion_times
            )
            or not isinstance(unorderable_completed_torrents, int)
            or isinstance(unorderable_completed_torrents, bool)
            or unorderable_completed_torrents < 0
        ):
            raise ValueError("completion-time context is invalid")
        self.completion_times = tuple(completion_times)
        self.unorderable_completed_torrents = unorderable_completed_torrents

    @staticmethod
    def _emit_json(event: Mapping[str, Any]) -> None:
        print(json.dumps(event, sort_keys=True, separators=(",", ":")), flush=True)

    def update(
        self,
        *,
        torrents_done: int,
        files_done: int,
        bytes_done: int,
        files_reused: int = 0,
        bytes_reused: int = 0,
        receipts_created: int = 0,
        failed_torrents: int = 0,
        event: str = "staging_progress",
        force: bool = False,
    ) -> bool:
        now = self.clock()
        if (
            self.last_emit_at is not None
            and not force
            and now - self.last_emit_at < self.interval_seconds
        ):
            return False

        update_rate = event == "staging_progress" or self.last_emit_at is None
        if update_rate and self.last_emit_at is not None and now > self.last_emit_at:
            sample_rate = max(0, bytes_done - self.last_emit_bytes) / (now - self.last_emit_at)
            self.bytes_per_second = (
                sample_rate
                if self.bytes_per_second is None
                else 0.5 * self.bytes_per_second + 0.5 * sample_rate
            )
        elif update_rate and now > self.started_at:
            self.bytes_per_second = max(0, bytes_done) / (now - self.started_at)

        total_bytes = self.totals.get("bytes")
        progress_bytes = max(0, bytes_done) + max(0, bytes_reused)
        if self.unorderable_completed_torrents > 0:
            total_bytes = None
        if self.unorderable_completed_torrents > 0:
            time_behind_seconds = None
        elif not self.completion_times:
            time_behind_seconds = 0 if self.totals.get("torrents") == 0 else None
        elif torrents_done >= len(self.completion_times):
            time_behind_seconds = 0
        else:
            time_behind_seconds = max(
                0,
                int(self.wall_clock() - self.completion_times[torrents_done]),
            )
        percent_complete = None
        if (
            isinstance(total_bytes, int)
            and not isinstance(total_bytes, bool)
            and total_bytes > 0
            and 0 <= progress_bytes <= total_bytes
        ):
            percent_complete = round(100 * progress_bytes / total_bytes, 1)
        eta_seconds = None
        if (
            isinstance(total_bytes, int)
            and not isinstance(total_bytes, bool)
            and total_bytes >= progress_bytes
            and self.bytes_per_second is not None
            and self.bytes_per_second > 0
        ):
            eta_seconds = math.ceil((total_bytes - progress_bytes) / self.bytes_per_second)

        self.emit_event(
            {
                "event": event,
                "elapsed_seconds": max(0, int(now - self.started_at)),
                "torrents_published": torrents_done,
                "torrents_total": self.totals.get("torrents"),
                "files_transferred": files_done,
                "files_reused": files_reused,
                "files_total": self.totals.get("files"),
                "bytes_transferred": max(0, bytes_done),
                "bytes_reused": max(0, bytes_reused),
                "bytes_total": total_bytes,
                "percent_complete": percent_complete,
                "bytes_per_second": (
                    round(self.bytes_per_second, 2)
                    if self.bytes_per_second is not None
                    else None
                ),
                "eta_seconds": eta_seconds,
                "time_behind_seconds": time_behind_seconds,
                "unorderable_completed_torrents": self.unorderable_completed_torrents,
                "receipts_created": receipts_created,
                "failed_torrents": failed_torrents,
            }
        )
        if event == "staging_progress" or self.last_emit_at is None:
            self.last_emit_at = now
            self.last_emit_bytes = max(0, bytes_done)
        return True



_CLEANUP_POLICY_RETRY_REASONS = {
    "incomplete_torrent",
    "below_retention_threshold",
    "private_ratio_below_floor",
    "private_ratio_missing",
    "private_ratio_malformed",
    "private_ratio_unavailable",
    "payload_files_missing",
    "file_metadata_invalid",
    "file_unmapped",
    "source_mapping_unverified",
    "source_file_shared",
    "source_ownership_unverified",
    "shared_file_unsafe",
    "tracker_classification_unknown",
    "tracker_ratio_unavailable",
}
_MAX_CLEANUP_RETRY_SECONDS = 60 * 60


def _torrent_key(torrent_id: int) -> str:
    if not isinstance(torrent_id, int) or isinstance(torrent_id, bool) or torrent_id <= 0:
        raise ValueError("torrent identifier is invalid")
    return hashlib.sha256(str(torrent_id).encode("ascii")).hexdigest()


def fingerprint_torrent(
    torrent: Mapping[str, Any],
    mappings: Any = None,
) -> str:
    """Hash the ordered source manifest and mapping without exposing their paths."""
    torrent_id = torrent.get("id")
    download_directory = torrent.get("download_directory")
    file_paths = torrent.get("file_paths")
    file_sizes = torrent.get("file_sizes")
    if (
        not isinstance(torrent_id, int)
        or isinstance(torrent_id, bool)
        or torrent_id <= 0
        or not isinstance(download_directory, str)
        or not isinstance(file_paths, list)
        or not file_paths
        or not isinstance(file_sizes, list)
        or len(file_sizes) != len(file_paths)
        or any(not isinstance(path, str) or "\0" in path for path in file_paths)
        or any(size is not None and (not isinstance(size, int) or isinstance(size, bool) or size < 0) for size in file_sizes)
    ):
        raise ValueError("torrent source manifest is invalid")
    normalized_mappings = (
        _validate_normalized_mappings(mappings)
        if mappings is not None
        else []
    )
    manifest = {
        "torrent_id": torrent_id,
        "download_directory": download_directory,
        "file_paths": file_paths,
        "file_sizes": file_sizes,
        "mappings": normalized_mappings,
    }
    encoded = json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _receipt_path(queue_root: str | Path, torrent_id: int) -> Path:
    return Path(queue_root) / f"{_torrent_key(torrent_id)}.json"


@contextmanager
def cleanup_queue_lock(queue_root: str | Path) -> Iterator[None]:
    """Serialize receipt read/modify/write operations across stage and cleanup."""
    root = Path(queue_root)
    root.mkdir(parents=True, mode=0o700, exist_ok=True)
    if root.is_symlink() or root.parent.is_symlink():
        raise OSError("cleanup queue directories must not be symlinks")
    lock_path = root.parent / ".cleanup-queue.lock"
    descriptor = os.open(
        lock_path,
        os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0),
        0o600,
    )
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise OSError("cleanup queue lock is not a regular file")
        with os.fdopen(descriptor, "r+") as lock_file:
            descriptor = -1
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
            yield
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def _write_receipt_atomic(path: Path, receipt: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    if path.parent.is_symlink():
        raise OSError("queue directory must not be a symlink")
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=".receipt-", delete=False
        ) as receipt_file:
            temporary_path = Path(receipt_file.name)
            os.fchmod(receipt_file.fileno(), 0o600)
            json.dump(dict(receipt), receipt_file, sort_keys=True, separators=(",", ":"))
            receipt_file.flush()
            os.fsync(receipt_file.fileno())
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


def write_staged_torrent_receipt(
    queue_root: str | Path,
    torrent_id: int,
    fingerprint: str,
    *,
    staged_at_ns: int,
) -> dict[str, Any]:
    """Atomically enqueue a torrent only after all of its files are published."""
    if not isinstance(fingerprint, str) or re.fullmatch(r"[0-9a-f]{64}", fingerprint) is None:
        raise ValueError("torrent fingerprint is invalid")
    if not isinstance(staged_at_ns, int) or isinstance(staged_at_ns, bool) or staged_at_ns <= 0:
        raise ValueError("staged timestamp is invalid")
    receipt = {
        "version": 1,
        "receipt_id": secrets.token_hex(16),
        "torrent_id": torrent_id,
        "fingerprint": fingerprint,
        "staged_at_ns": staged_at_ns,
        "attempts": 0,
        "next_attempt_ns": staged_at_ns,
    }
    path = _receipt_path(queue_root, torrent_id)
    with cleanup_queue_lock(queue_root):
        _write_receipt_atomic(path, receipt)
    return {**receipt, "receipt_path": str(path)}


def _read_valid_torrent_receipts(queue_root: str | Path) -> list[dict[str, Any]]:
    """Read valid receipts regardless of retry time; skip malformed and symlinked files."""
    root = Path(queue_root)
    if not root.exists() or root.is_symlink() or not root.is_dir():
        return []
    receipts = []
    for path in sorted(root.glob("*.json")):
        try:
            if not stat.S_ISREG(os.lstat(path).st_mode):
                continue
            receipt = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            continue
        if not isinstance(receipt, Mapping):
            continue
        torrent_id = receipt.get("torrent_id")
        fingerprint = receipt.get("fingerprint")
        staged_at_ns = receipt.get("staged_at_ns")
        receipt_id = receipt.get("receipt_id")
        attempts = receipt.get("attempts")
        next_attempt_ns = receipt.get("next_attempt_ns")
        if (
            not isinstance(receipt.get("version"), int)
            or isinstance(receipt.get("version"), bool)
            or receipt.get("version") != 1
            or not isinstance(torrent_id, int)
            or isinstance(torrent_id, bool)
            or torrent_id <= 0
            or not isinstance(receipt_id, str)
            or re.fullmatch(r"[0-9a-f]{32}", receipt_id) is None
            or not isinstance(fingerprint, str)
            or re.fullmatch(r"[0-9a-f]{64}", fingerprint) is None
            or not isinstance(staged_at_ns, int)
            or isinstance(staged_at_ns, bool)
            or staged_at_ns <= 0
            or not isinstance(attempts, int)
            or isinstance(attempts, bool)
            or attempts < 0
            or not isinstance(next_attempt_ns, int)
            or isinstance(next_attempt_ns, bool)
            or next_attempt_ns < staged_at_ns
            or path != _receipt_path(root, torrent_id)
        ):
            continue
        receipts.append(dict(receipt))
    return sorted(receipts, key=lambda receipt: (receipt["next_attempt_ns"], receipt["staged_at_ns"]))


def read_pending_torrent_receipts(
    queue_root: str | Path,
    *,
    now_ns: int,
) -> list[dict[str, Any]]:
    """Read only valid, due receipts; malformed or symlinked entries fail closed."""
    return [
        receipt
        for receipt in _read_valid_torrent_receipts(queue_root)
        if receipt["next_attempt_ns"] <= now_ns
    ]


def defer_staged_torrent_receipt(
    queue_root: str | Path,
    receipt: Mapping[str, Any],
    *,
    now_ns: int,
    reason: str,
) -> dict[str, Any] | None:
    """Retain the exact receipt and schedule a bounded retry for a safe block reason."""
    torrent_id = receipt.get("torrent_id")
    fingerprint = receipt.get("fingerprint")
    if not isinstance(torrent_id, int) or isinstance(torrent_id, bool) or not isinstance(fingerprint, str):
        return None
    path = _receipt_path(queue_root, torrent_id)
    with cleanup_queue_lock(queue_root):
        try:
            current = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            return None
        if (
            not isinstance(current, dict)
            or current.get("fingerprint") != fingerprint
            or current.get("receipt_id") != receipt.get("receipt_id")
        ):
            return None
        attempts = current.get("attempts", 0)
        if not isinstance(attempts, int) or isinstance(attempts, bool) or attempts < 0:
            return None
        delay_seconds = (
            _MAX_CLEANUP_RETRY_SECONDS
            if reason in _CLEANUP_POLICY_RETRY_REASONS
            else min(60 * (2 ** min(attempts, 6)), _MAX_CLEANUP_RETRY_SECONDS)
        )
        current["attempts"] = attempts + 1
        current["last_reason"] = reason if reason.isidentifier() else "runtime_cleanup_failed"
        current["next_attempt_ns"] = now_ns + delay_seconds * 1_000_000_000
        _write_receipt_atomic(path, current)
        return current


def ack_staged_torrent_receipt(
    queue_root: str | Path,
    expected_receipt: Mapping[str, Any],
) -> bool:
    """Remove a queue entry only if it is still the exact staged receipt."""
    torrent_id = expected_receipt.get("torrent_id")
    try:
        path = _receipt_path(queue_root, torrent_id)
        with cleanup_queue_lock(queue_root):
            if not stat.S_ISREG(os.lstat(path).st_mode):
                return False
            current = json.loads(path.read_text(encoding="utf-8"))
            if (
                not isinstance(current, Mapping)
                or current.get("fingerprint") != expected_receipt.get("fingerprint")
                or current.get("receipt_id") != expected_receipt.get("receipt_id")
            ):
                return False
            path.unlink()
            return True
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
        return False


@contextmanager
def torrent_operation_lock(
    runtime_root: str | Path,
    torrent_id: int,
    *,
    blocking: bool = True,
) -> Iterator[None]:
    """Serialize stage/cleanup for one torrent while allowing unrelated torrents to overlap."""
    lock_root = Path(runtime_root) / "locks"
    lock_root.mkdir(parents=True, mode=0o700, exist_ok=True)
    if lock_root.is_symlink():
        raise OSError("torrent lock directory must not be a symlink")
    lock_path = lock_root / f"{_torrent_key(torrent_id)}.lock"
    flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(lock_path, flags, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise OSError("torrent lock is not a regular file")
        with os.fdopen(descriptor, "r+") as lock_file:
            descriptor = -1
            lock_flags = fcntl.LOCK_EX if blocking else fcntl.LOCK_EX | fcntl.LOCK_NB
            fcntl.flock(lock_file.fileno(), lock_flags)
            yield
    finally:
        if descriptor >= 0:
            os.close(descriptor)


def cleanup_legacy_stage_workspaces(staging_root: str | Path) -> int:
    """Remove only unmanifested workspaces left by the pre-resume staging runner."""
    root = Path(staging_root).absolute()
    if root.is_symlink() or not root.is_dir():
        raise OSError("staging root must be a regular directory")
    removed = 0
    for path in root.iterdir():
        if not path.name.startswith(".incoming-") or path.name.startswith(".incoming-v1-"):
            continue
        metadata = os.lstat(path)
        if stat.S_ISLNK(metadata.st_mode):
            raise OSError("legacy staging workspace must not be a symlink")
        if stat.S_ISDIR(metadata.st_mode):
            import shutil

            shutil.rmtree(path)
            removed += 1
    return removed


def prepare_torrent_workspace(
    staging_root: str | Path,
    torrent_id: int,
    fingerprint: str,
) -> Path:
    """Reuse rsync partial data only for the same torrent manifest."""
    root = Path(staging_root).absolute()
    if root.is_symlink() or not root.is_dir():
        raise OSError("staging root must be a regular directory")
    workspace = root / f".incoming-v1-{_torrent_key(torrent_id)}"
    if workspace.exists() or workspace.is_symlink():
        metadata = os.lstat(workspace)
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
            raise OSError("torrent workspace must be a regular directory")
        manifest_path = workspace / ".manifest.json"
        try:
            manifest_metadata = os.lstat(manifest_path)
            if not stat.S_ISREG(manifest_metadata.st_mode):
                raise ValueError("workspace manifest is not regular")
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError, json.JSONDecodeError):
            manifest = None
        if not (
            isinstance(manifest, Mapping)
            and manifest.get("version") == 1
            and manifest.get("torrent_id") == torrent_id
            and manifest.get("fingerprint") == fingerprint
        ):
            import shutil

            shutil.rmtree(workspace)
    workspace.mkdir(mode=0o700, exist_ok=True)
    resolved_workspace = workspace.resolve()
    if os.path.commonpath((str(root), str(resolved_workspace))) != str(root):
        raise OSError("torrent workspace escapes the staging root")
    manifest_path = workspace / ".manifest.json"
    if not manifest_path.exists():
        _write_receipt_atomic(
            manifest_path,
            {"version": 1, "torrent_id": torrent_id, "fingerprint": fingerprint},
        )
    return workspace


def _ensure_destination_within_root(destination: Path, root: Path) -> None:
    resolved_root = root.resolve()
    resolved_parent = destination.parent.resolve()
    try:
        contained = os.path.commonpath((str(resolved_root), str(resolved_parent))) == str(
            resolved_root
        )
    except ValueError:
        contained = False
    if not contained:
        raise OSError("staging destination escapes the staging root")


def staged_file_matches_source(
    remote_path: str,
    local_path: str | Path,
    expected_size: int | None,
    source_stat: Callable[[str], Mapping[str, Any] | None],
) -> bool:
    """Reuse a local staging file only when strict remote size/mtime facts match."""
    if not callable(source_stat):
        return False
    local_path = Path(local_path)
    try:
        local_metadata = os.lstat(local_path)
    except OSError:
        return False
    if not stat.S_ISREG(local_metadata.st_mode):
        return False
    try:
        remote_metadata = source_stat(remote_path)
    except Exception:
        return False
    if (
        not isinstance(remote_metadata, Mapping)
        or remote_metadata.get("regular_file") is not True
        or not isinstance(remote_metadata.get("size"), int)
        or isinstance(remote_metadata.get("size"), bool)
        or not isinstance(remote_metadata.get("mtime_ns"), int)
        or isinstance(remote_metadata.get("mtime_ns"), bool)
    ):
        return False
    remote_size = remote_metadata["size"]
    if expected_size is not None and remote_size != expected_size:
        return False
    return local_metadata.st_size == remote_size and local_metadata.st_mtime_ns == remote_metadata["mtime_ns"]


def _stage_torrent_files(
    transfers: Sequence[Mapping[str, Any]],
    root: Path,
    workspace: Path,
    transfer: Callable[[str, Path, Callable[[int], None]], None],
    reporter: StageProgressReporter,
    counters: dict[str, int],
    source_stat: Callable[[str], Mapping[str, Any] | None] | None = None,
) -> None:
    staged_files: list[tuple[Path, Path]] = []
    for index, transfer_plan in enumerate(transfers):
        local_destination = Path(transfer_plan["local_destination"])
        _ensure_destination_within_root(local_destination, root)
        if source_stat is not None and staged_file_matches_source(
            transfer_plan["remote_source"],
            local_destination,
            transfer_plan.get("size_bytes"),
            source_stat,
        ):
            reused_bytes = os.lstat(local_destination).st_size
            counters["bytes_reused"] += reused_bytes
            counters["files_reused"] += 1
            reporter.update(
                torrents_done=counters["torrents_done"],
                files_done=counters["files_done"],
                bytes_done=counters["bytes_done"],
                files_reused=counters["files_reused"],
                bytes_reused=counters["bytes_reused"],
                receipts_created=counters.get("receipts_created", 0),
            )
            continue
        temporary_file = workspace / f"payload-{index}"

        def report_file_progress(current_file_bytes: int) -> None:
            reporter.update(
                torrents_done=counters["torrents_done"],
                files_done=counters["files_done"],
                bytes_done=counters["bytes_done"] + max(0, current_file_bytes),
                files_reused=counters["files_reused"],
                bytes_reused=counters["bytes_reused"],
                receipts_created=counters.get("receipts_created", 0),
            )

        transfer(transfer_plan["remote_source"], temporary_file, report_file_progress)
        if not temporary_file.is_file():
            raise OSError("transfer did not produce a regular payload")
        counters["bytes_done"] += temporary_file.stat().st_size
        counters["files_done"] += 1
        staged_files.append(
            (temporary_file, Path(transfer_plan["local_destination"]))
        )

    backups: list[tuple[Path, Path]] = []
    published: list[Path] = []
    try:
        for index, (temporary_file, local_destination) in enumerate(staged_files):
            local_destination.parent.mkdir(parents=True, exist_ok=True)
            _ensure_destination_within_root(local_destination, root)
            if local_destination.exists():
                if not local_destination.is_file():
                    raise OSError("staging destination is not a regular file")
                backup = workspace / f"backup-{index}"
                os.replace(local_destination, backup)
                backups.append((backup, local_destination))
            os.replace(temporary_file, local_destination)
            published.append(local_destination)
    except OSError:
        for local_destination in reversed(published):
            local_destination.unlink(missing_ok=True)
        for backup, local_destination in reversed(backups):
            if backup.exists():
                os.replace(backup, local_destination)
        raise

    import shutil

    shutil.rmtree(workspace)


def stage_completed_downloads(
    torrents: Sequence[Mapping[str, Any]],
    mappings: Any,
    transfer: Callable[[str, Path, Callable[[int], None]], None],
    *,
    staging_root: str | Path = STAGING_ROOT,
    runtime_root: str | Path | None = None,
    source_stat: Callable[[str], Mapping[str, Any] | None] | None = None,
    progress_reporter: StageProgressReporter | None = None,
    on_torrent_staged: Callable[[Mapping[str, Any]], None] | None = None,
) -> dict[str, Any]:
    """Copy each complete mapped torrent as an atomic, independently reportable unit."""
    plan = build_staging_plan(torrents, mappings, staging_root=staging_root)
    reporter = progress_reporter or StageProgressReporter(plan["totals"])
    reporter.set_completion_context(
        [planned["done_date"] for planned in plan["torrents"]],
        plan["counts"]["skipped_unknown_completion_time"],
    )
    root = Path(staging_root).absolute()
    root.mkdir(parents=True, exist_ok=True)
    if root.is_symlink():
        raise OSError("staging root must not be a symbolic link")
    root = root.resolve()
    cleanup_legacy_stage_workspaces(root)

    result = {
        **plan["counts"],
        "staged": 0,
        "failed": 0,
        "reused_files": 0,
    }
    counters = {
        "torrents_done": 0,
        "files_done": 0,
        "bytes_done": 0,
        "files_reused": 0,
        "bytes_reused": 0,
        "receipts_created": 0,
    }
    reporter.update(**counters, event="staging_started", force=True)

    for planned_torrent in plan["torrents"]:
        torrent = planned_torrent["torrent"]
        torrent_id = planned_torrent["torrent_id"]
        lock = (
            torrent_operation_lock(runtime_root, torrent_id)
            if runtime_root is not None
            else nullcontext()
        )
        try:
            with lock:
                workspace = prepare_torrent_workspace(
                    root,
                    torrent_id,
                    planned_torrent["fingerprint"],
                )
                _stage_torrent_files(
                    planned_torrent["transfers"],
                    root,
                    workspace,
                    transfer,
                    reporter,
                    counters,
                    source_stat,
                )
                result["reused_files"] = counters["files_reused"]
                if on_torrent_staged is not None:
                    on_torrent_staged(torrent)
                    counters["receipts_created"] += 1
            result["staged"] += 1
            counters["torrents_done"] += 1
            reporter.update(
                **counters,
                event="torrent_staged",
                force=True,
            )
        except (OSError, subprocess.SubprocessError, ValueError, TypeError):
            result["failed"] += 1
            result["reused_files"] = counters["files_reused"]
            reporter.update(
                **counters,
                failed_torrents=result["failed"],
                event="torrent_failed",
                force=True,
            )

    reporter.update(
        **counters,
        failed_torrents=result["failed"],
        event="staging_completed" if result["failed"] == 0 else "staging_failed",
        force=True,
    )
    result.update(
        {
            "torrents_total": plan["totals"].get("torrents"),
            "files_total": plan["totals"].get("files"),
            "bytes_total": plan["totals"].get("bytes"),
            "files_transferred": counters["files_done"],
            "bytes_transferred": counters["bytes_done"],
            "files_reused": counters["files_reused"],
            "bytes_reused": counters["bytes_reused"],
            "receipts_created": counters["receipts_created"],
        }
    )
    return result


def _read_secret_file(path: str) -> str:
    try:
        value = Path(path).read_text(encoding="utf-8").rstrip("\r\n")
    except (OSError, UnicodeError):
        raise StagingConfigurationError("credential_unavailable") from None
    if not value.strip() or any(character in value for character in "\0\r\n"):
        raise StagingConfigurationError("credential_unavailable")
    return value


def _read_known_hosts_file(path: str) -> str:
    try:
        value = Path(path).read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        raise StagingConfigurationError("ssh_config_missing") from None
    if not value or "\0" in value:
        raise StagingConfigurationError("ssh_config_missing")
    return value


def _stage_from_runtime_files(
    secret_paths: Mapping[str, str],
    key_path: str,
    *,
    ssh_port: Any = 22,
    ssh_executable: str,
    ssh_keygen_executable: str,
    rsync_executable: str,
    process_runner: Callable[..., Any] = subprocess.run,
    progress_runner: Callable[[Sequence[str], Callable[[int], None]], None] = run_rsync_with_progress,
    staging_root: str | Path = STAGING_ROOT,
    runtime_root: str | Path | None = None,
    cleanup_queue_root: str | Path | None = None,
) -> dict[str, int]:
    try:
        rpc_url = _read_secret_file(secret_paths["rpc_url"])
        download_root = _read_secret_file(secret_paths["download_root"])
        host = _read_secret_file(secret_paths["ssh_host"])
        ssh_username = _read_secret_file(secret_paths["ssh_username"])
        known_hosts = _read_known_hosts_file(secret_paths["known_hosts"])
        rpc_username = _read_secret_file(secret_paths["rpc_username"])
        rpc_password = _read_secret_file(secret_paths["rpc_password"])
    except (KeyError, TypeError):
        raise StagingConfigurationError("credential_unavailable") from None

    rpc_url, mappings = validate_staging_config(
        rpc_url, download_root, rpc_username, rpc_password
    )
    try:
        port = normalize_ssh_port(ssh_port)
    except StagingConfigurationError:
        raise
    if (
        not isinstance(host, str)
        or not host
        or any(character.isspace() or character in "\0@:" for character in host)
        or not isinstance(ssh_username, str)
        or not ssh_username
        or any(character.isspace() or character in "\0@:" for character in ssh_username)
        or not isinstance(known_hosts, str)
        or not known_hosts.strip()
        or "\0" in known_hosts
    ):
        raise StagingConfigurationError("ssh_config_missing")
    if not Path(key_path).is_file():
        raise StagingConfigurationError("ssh_key_unavailable")

    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as known_hosts_file:
        os.chmod(known_hosts_file.name, 0o600)
        known_hosts_file.write(known_hosts + "\n")
        known_hosts_file.flush()
        known_hosts_alias = host if port == 22 else f"[{host}]:{port}"
        key_check = process_runner(
            [ssh_keygen_executable, "-F", known_hosts_alias, "-f", known_hosts_file.name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if key_check.returncode != 0:
            raise StagingConfigurationError("ssh_host_key_unavailable")

        ssh_arguments = [
            ssh_executable,
            "-i",
            key_path,
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
        ]
        ssh_command = shlex.join(ssh_arguments)
        source_stat = make_remote_source_stat(
            ssh_arguments,
            ssh_username,
            host,
            process_runner=process_runner,
        )

        try:
            from transmission_rpc import TransmissionRPC

            rpc = TransmissionRPC(rpc_url, rpc_username, rpc_password)
            torrents = rpc.get_torrents()
        except Exception:
            raise StagingConfigurationError("rpc_unavailable") from None

        def transfer(
            remote_source: str,
            local_temporary: Path,
            report_progress: Callable[[int], None],
        ) -> None:
            remote = f"{ssh_username}@{host}:{remote_source}"
            arguments = build_rsync_arguments(
                rsync_executable, ssh_command, remote, str(local_temporary)
            )
            progress_runner(arguments, report_progress)

        def enqueue_staged_torrent(torrent: Mapping[str, Any]) -> None:
            if cleanup_queue_root is None:
                return
            write_staged_torrent_receipt(
                cleanup_queue_root,
                torrent["id"],
                fingerprint_torrent(torrent, mappings),
                staged_at_ns=time.time_ns(),
            )

        return stage_completed_downloads(
            torrents,
            mappings,
            transfer,
            staging_root=staging_root,
            runtime_root=runtime_root,
            source_stat=source_stat,
            on_torrent_staged=enqueue_staged_torrent if cleanup_queue_root is not None else None,
        )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage-downloads", action="store_true")
    parser.add_argument("--rpc-url", required=True)
    parser.add_argument("--download-root", required=True)
    parser.add_argument("--ssh-host", required=True)
    parser.add_argument("--ssh-username", required=True)
    parser.add_argument("--ssh-port", type=int, default=22)
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--ssh-key", required=True)
    parser.add_argument("--rpc-username", required=True)
    parser.add_argument("--rpc-password", required=True)
    parser.add_argument("--ssh", required=True)
    parser.add_argument("--ssh-keygen", required=True)
    parser.add_argument("--rsync", required=True)
    parser.add_argument("--cleanup-queue-root")
    args = parser.parse_args(argv)
    if not args.stage_downloads:
        print("staging failed reason=operation_required", file=sys.stderr)
        return 2

    try:
        result = _stage_from_runtime_files(
            {
                "rpc_url": args.rpc_url,
                "download_root": args.download_root,
                "ssh_host": args.ssh_host,
                "ssh_username": args.ssh_username,
                "ssh_port": args.ssh_port,
                "known_hosts": args.known_hosts,
                "rpc_username": args.rpc_username,
                "rpc_password": args.rpc_password,
            },
            args.ssh_key,
            ssh_port=args.ssh_port,
            ssh_executable=args.ssh,
            ssh_keygen_executable=args.ssh_keygen,
            rsync_executable=args.rsync,
            runtime_root=RUNTIME_ROOT,
            cleanup_queue_root=args.cleanup_queue_root,
        )
    except StagingConfigurationError as error:
        print(f"staging failed reason={error.reason}", file=sys.stderr)
        return 1
    except (OSError, subprocess.SubprocessError):
        print("staging failed reason=local_io_failure", file=sys.stderr)
        return 1

    print(
        json.dumps(
            {"event": "staging_run_result", **result},
            sort_keys=True,
            separators=(",", ":"),
        ),
        flush=True,
    )
    return 1 if result["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
