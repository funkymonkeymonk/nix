"""Pause Transmission downloads before the Ultra account quota is exhausted."""

import argparse
import importlib.util
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

from transmission_rpc import TransmissionRPC


STATE_VERSION = 1
TORRENT_HASH_PATTERN = re.compile(r"[0-9a-fA-F]{40}")
COUNTER_FIELDS = (
    "pause_events_total",
    "resume_events_total",
    "probe_failures_total",
    "rpc_failures_total",
)
COUNTER_METRICS = {
    "pause_events_total": "ultra_seedbox_download_guard_pauses_total",
    "resume_events_total": "ultra_seedbox_download_guard_resumes_total",
    "probe_failures_total": "ultra_seedbox_download_guard_probe_failures_total",
    "rpc_failures_total": "ultra_seedbox_download_guard_rpc_failures_total",
}


def new_guard_state() -> dict[str, Any]:
    """Return an empty guard state with stable aggregate counters."""
    return {
        "version": STATE_VERSION,
        "active": False,
        "paused_hashes": [],
        **{field: 0 for field in COUNTER_FIELDS},
    }


def _valid_hash(value: Any) -> str | None:
    if not isinstance(value, str) or TORRENT_HASH_PATTERN.fullmatch(value) is None:
        return None
    return value.upper()


def _normalize_guard_state(value: Any) -> dict[str, Any] | None:
    if (
        not isinstance(value, Mapping)
        or type(value.get("version")) is not int
        or value.get("version") != STATE_VERSION
    ):
        return None
    active = value.get("active")
    paused_hashes = value.get("paused_hashes")
    if type(active) is not bool or not isinstance(paused_hashes, list):
        return None
    normalized_hashes = []
    for torrent_hash in paused_hashes:
        normalized_hash = _valid_hash(torrent_hash)
        if normalized_hash is None:
            return None
        normalized_hashes.append(normalized_hash)
    counters = {}
    for field in COUNTER_FIELDS:
        count = value.get(field, 0)
        if not isinstance(count, int) or isinstance(count, bool) or count < 0:
            return None
        counters[field] = count
    return {
        "version": STATE_VERSION,
        "active": active,
        "paused_hashes": sorted(set(normalized_hashes)),
        **counters,
    }


def load_guard_state(state_path: str | Path) -> dict[str, Any] | None:
    """Read valid state; distinguish a missing file from corrupted state."""
    path = Path(state_path)
    try:
        metadata = os.lstat(path)
    except FileNotFoundError:
        return new_guard_state()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    return _normalize_guard_state(value)


def save_guard_state(state_path: str | Path, state: Mapping[str, Any]) -> None:
    """Atomically store validated state with owner-only permissions."""
    normalized = _normalize_guard_state(state)
    if normalized is None:
        raise ValueError("quota guard state is invalid")
    path = Path(state_path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        existing = os.lstat(path)
    except FileNotFoundError:
        existing = None
    if existing is not None and (
        stat.S_ISLNK(existing.st_mode) or not stat.S_ISREG(existing.st_mode)
    ):
        raise OSError("quota guard state destination must be a regular file")

    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="ascii",
            dir=path.parent,
            prefix=f".{path.name}-",
            delete=False,
        ) as state_file:
            temporary_path = Path(state_file.name)
            os.fchmod(state_file.fileno(), 0o600)
            json.dump(normalized, state_file, sort_keys=True, separators=(",", ":"))
            state_file.write("\n")
            state_file.flush()
            os.fsync(state_file.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except FileNotFoundError:
                pass


def _validate_thresholds(pause_at_bytes: int, resume_below_bytes: int) -> None:
    if (
        not isinstance(pause_at_bytes, int)
        or isinstance(pause_at_bytes, bool)
        or pause_at_bytes <= 0
        or not isinstance(resume_below_bytes, int)
        or isinstance(resume_below_bytes, bool)
        or resume_below_bytes <= 0
        or resume_below_bytes >= pause_at_bytes
    ):
        raise ValueError("quota guard thresholds must be positive and resume below pause")


def plan_guard_actions(
    used_bytes: int | None,
    torrents: Sequence[Mapping[str, Any]],
    state: Mapping[str, Any],
    *,
    pause_at_bytes: int,
    resume_below_bytes: int,
) -> dict[str, Any]:
    """Plan idempotent torrent actions using quota hysteresis and owned hashes."""
    _validate_thresholds(pause_at_bytes, resume_below_bytes)
    if used_bytes is not None and (
        not isinstance(used_bytes, int)
        or isinstance(used_bytes, bool)
        or used_bytes < 0
    ):
        raise ValueError("quota usage must be a non-negative byte count or unknown")
    normalized_state = _normalize_guard_state(state)
    if normalized_state is None:
        raise ValueError("quota guard state is invalid")
    if not isinstance(torrents, Sequence) or isinstance(torrents, (str, bytes)):
        raise ValueError("Transmission torrent list is invalid")

    active = normalized_state["active"]
    paused_hashes = set(normalized_state["paused_hashes"])
    if used_bytes is None:
        return {
            "active": active,
            "paused_hashes": sorted(paused_hashes),
            "pause_hashes": [],
            "resume_hashes": [],
        }

    if active and used_bytes < resume_below_bytes:
        visible_hashes = {
            torrent_hash
            for torrent in torrents
            if isinstance(torrent, Mapping)
            and (torrent_hash := _valid_hash(torrent.get("download_id"))) is not None
        }
        resume_hashes = sorted(paused_hashes & visible_hashes)
        return {
            "active": False,
            "paused_hashes": [],
            "pause_hashes": [],
            "resume_hashes": resume_hashes,
        }

    if not active and used_bytes < pause_at_bytes:
        return {
            "active": False,
            "paused_hashes": [],
            "pause_hashes": [],
            "resume_hashes": [],
        }

    pause_hashes = set()
    for torrent in torrents:
        if not isinstance(torrent, Mapping):
            continue
        status = torrent.get("status")
        candidate = torrent.get("candidate")
        torrent_hash = _valid_hash(torrent.get("download_id"))
        if (
            isinstance(status, int)
            and not isinstance(status, bool)
            and status in (3, 4)
            and isinstance(candidate, Mapping)
            and candidate.get("complete") is False
            and torrent_hash is not None
        ):
            pause_hashes.add(torrent_hash)

    paused_hashes.update(pause_hashes)
    return {
        "active": True,
        "paused_hashes": sorted(paused_hashes),
        "pause_hashes": sorted(pause_hashes),
        "resume_hashes": [],
    }


def render_guard_metrics(
    state: Mapping[str, Any],
    *,
    used_bytes: int | None,
    probe_success: bool,
    rpc_success: bool,
    sample_timestamp_seconds: int,
) -> str:
    """Render aggregate Prometheus gauges/counters without torrent identity."""
    normalized = _normalize_guard_state(state)
    if normalized is None:
        raise ValueError("quota guard state is invalid")
    if used_bytes is not None and (
        not isinstance(used_bytes, int)
        or isinstance(used_bytes, bool)
        or used_bytes < 0
    ):
        raise ValueError("quota usage is invalid")
    if (
        type(probe_success) is not bool
        or type(rpc_success) is not bool
        or not isinstance(sample_timestamp_seconds, int)
        or isinstance(sample_timestamp_seconds, bool)
        or sample_timestamp_seconds <= 0
    ):
        raise ValueError("quota guard metric sample is invalid")

    lines = [
        "# HELP ultra_seedbox_download_guard_active Whether the quota guard is holding downloads.",
        "# TYPE ultra_seedbox_download_guard_active gauge",
        f"ultra_seedbox_download_guard_active {int(normalized['active'])}",
        "# HELP ultra_seedbox_download_guard_paused_torrents Number of hashes owned by the quota guard.",
        "# TYPE ultra_seedbox_download_guard_paused_torrents gauge",
        f"ultra_seedbox_download_guard_paused_torrents {len(normalized['paused_hashes'])}",
    ]
    for field in COUNTER_FIELDS:
        metric = COUNTER_METRICS[field]
        lines.extend([f"# TYPE {metric} counter", f"{metric} {normalized[field]}"])
    lines.extend(
        [
            "# HELP ultra_seedbox_download_guard_probe_success Whether the live quota probe succeeded.",
            "# TYPE ultra_seedbox_download_guard_probe_success gauge",
            f"ultra_seedbox_download_guard_probe_success {int(probe_success)}",
            "# HELP ultra_seedbox_download_guard_rpc_success Whether the Transmission RPC check succeeded.",
            "# TYPE ultra_seedbox_download_guard_rpc_success gauge",
            f"ultra_seedbox_download_guard_rpc_success {int(rpc_success)}",
            "# HELP ultra_seedbox_download_guard_sample_timestamp_seconds Unix time of the last guard cycle.",
            "# TYPE ultra_seedbox_download_guard_sample_timestamp_seconds gauge",
            f"ultra_seedbox_download_guard_sample_timestamp_seconds {sample_timestamp_seconds}",
        ]
    )
    if used_bytes is not None:
        lines.extend(
            [
                "# HELP ultra_seedbox_download_guard_used_bytes Live account quota usage in bytes.",
                "# TYPE ultra_seedbox_download_guard_used_bytes gauge",
                f"ultra_seedbox_download_guard_used_bytes {used_bytes}",
            ]
        )
    return "\n".join(lines) + "\n"


def write_guard_metrics(metrics_path: str | Path, contents: str) -> None:
    """Atomically publish aggregate guard metrics with group-readable mode."""
    path = Path(metrics_path)
    if path.is_symlink():
        raise OSError("quota guard metrics destination must not be a symlink")
    try:
        existing = os.lstat(path)
    except FileNotFoundError:
        existing = None
    if existing is not None and not stat.S_ISREG(existing.st_mode):
        raise OSError("quota guard metrics destination must be a regular file")

    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="ascii",
            dir=path.parent,
            prefix=".ultra-space-guard-",
            suffix=".prom",
            delete=False,
        ) as metrics_file:
            temporary_path = Path(metrics_file.name)
            os.fchmod(metrics_file.fileno(), 0o640)
            metrics_file.write(contents)
            metrics_file.flush()
            os.fsync(metrics_file.fileno())
        os.replace(temporary_path, path)
        temporary_path = None
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except FileNotFoundError:
                pass


def run_guard_cycle(
    quota_probe: Callable[[], Mapping[str, Any] | None],
    transmission_rpc: Any,
    state_path: str | Path,
    metrics_path: str | Path,
    *,
    pause_at_bytes: int,
    resume_below_bytes: int,
    sample_timestamp_seconds: int | None = None,
) -> dict[str, Any]:
    """Probe, plan, and apply one idempotent guard cycle, preserving failures safely."""
    _validate_thresholds(pause_at_bytes, resume_below_bytes)
    sample_timestamp_seconds = (
        int(time.time()) if sample_timestamp_seconds is None else sample_timestamp_seconds
    )
    if (
        not isinstance(sample_timestamp_seconds, int)
        or isinstance(sample_timestamp_seconds, bool)
        or sample_timestamp_seconds <= 0
    ):
        raise ValueError("quota guard sample timestamp is invalid")
    state = load_guard_state(state_path)
    if state is None:
        return {"status": "state_invalid", "active": None, "paused_torrents": None}

    def publish(
        *,
        current_state: Mapping[str, Any],
        used_bytes: int | None,
        probe_success: bool,
        rpc_success: bool,
    ) -> None:
        write_guard_metrics(
            metrics_path,
            render_guard_metrics(
                current_state,
                used_bytes=used_bytes,
                probe_success=probe_success,
                rpc_success=rpc_success,
                sample_timestamp_seconds=sample_timestamp_seconds,
            ),
        )

    try:
        probe_result = quota_probe()
    except Exception:
        probe_result = None
    used_bytes = (
        probe_result.get("used_bytes") if isinstance(probe_result, Mapping) else None
    )
    if (
        not isinstance(used_bytes, int)
        or isinstance(used_bytes, bool)
        or used_bytes < 0
    ):
        failed_state = dict(state)
        failed_state["probe_failures_total"] += 1
        save_guard_state(state_path, failed_state)
        publish(
            current_state=failed_state,
            used_bytes=None,
            probe_success=False,
            rpc_success=False,
        )
        return {
            "status": "quota_probe_failed",
            "active": failed_state["active"],
            "paused_torrents": len(failed_state["paused_hashes"]),
            "used_bytes": None,
        }

    try:
        torrents = transmission_rpc.get_torrents()
        decision = plan_guard_actions(
            used_bytes,
            torrents,
            state,
            pause_at_bytes=pause_at_bytes,
            resume_below_bytes=resume_below_bytes,
        )
    except Exception:
        failed_state = dict(state)
        failed_state["rpc_failures_total"] += 1
        save_guard_state(state_path, failed_state)
        publish(
            current_state=failed_state,
            used_bytes=used_bytes,
            probe_success=True,
            rpc_success=False,
        )
        return {
            "status": "rpc_failed",
            "active": failed_state["active"],
            "paused_torrents": len(failed_state["paused_hashes"]),
            "used_bytes": used_bytes,
        }

    pause_hashes = decision["pause_hashes"]
    resume_hashes = decision["resume_hashes"]
    try:
        if pause_hashes:
            transmission_rpc.stop_torrents(pause_hashes)
        if resume_hashes:
            transmission_rpc.start_torrents(resume_hashes)
    except Exception:
        failed_state = dict(state)
        failed_state["rpc_failures_total"] += 1
        if pause_hashes:
            failed_state["active"] = decision["active"]
            failed_state["paused_hashes"] = decision["paused_hashes"]
        save_guard_state(state_path, failed_state)
        publish(
            current_state=failed_state,
            used_bytes=used_bytes,
            probe_success=True,
            rpc_success=False,
        )
        return {
            "status": "rpc_failed",
            "active": failed_state["active"],
            "paused_torrents": len(failed_state["paused_hashes"]),
            "used_bytes": used_bytes,
        }

    next_state = dict(state)
    next_state["active"] = decision["active"]
    next_state["paused_hashes"] = decision["paused_hashes"]
    next_state["pause_events_total"] += len(pause_hashes)
    next_state["resume_events_total"] += len(resume_hashes)
    save_guard_state(state_path, next_state)
    publish(
        current_state=next_state,
        used_bytes=used_bytes,
        probe_success=True,
        rpc_success=True,
    )
    return {
        "status": "ok",
        "active": next_state["active"],
        "paused_torrents": len(next_state["paused_hashes"]),
        "used_bytes": used_bytes,
    }


def _load_runtime_module(name: str, filename: str) -> Any:
    module = sys.modules.get(name)
    if module is not None:
        return module
    path = Path(__file__).with_name(filename)
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError("quota guard runtime dependency is unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(name, None)
        raise RuntimeError("quota guard runtime dependency is unavailable") from None
    return module


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rpc-url", required=True)
    parser.add_argument("--rpc-username", required=True)
    parser.add_argument("--rpc-password", required=True)
    parser.add_argument("--ssh-host", required=True)
    parser.add_argument("--ssh-username", required=True)
    parser.add_argument("--known-hosts", required=True)
    parser.add_argument("--ssh-key", required=True)
    parser.add_argument("--ssh-port", type=int, default=22)
    parser.add_argument("--ssh", required=True)
    parser.add_argument("--ssh-keygen", required=True)
    parser.add_argument("--state-file", required=True)
    parser.add_argument("--metrics-path", required=True)
    parser.add_argument("--pause-at-bytes", type=int, required=True)
    parser.add_argument("--resume-below-bytes", type=int, required=True)
    args = parser.parse_args(argv)

    try:
        cleanup = _load_runtime_module("ultra_media_cleanup", "ultra-media-cleanup.py")
        staging = cleanup._load_runtime_module(
            "ultra_media_download_stage", "ultra-media-download-stage.py"
        )
        secret_paths = {
            "ssh_host": args.ssh_host,
            "ssh_username": args.ssh_username,
            "known_hosts": args.known_hosts,
        }
        rpc_url = staging._read_secret_file(args.rpc_url)
        rpc_username = staging._read_secret_file(args.rpc_username)
        rpc_password = staging._read_secret_file(args.rpc_password)
        rpc = TransmissionRPC(rpc_url, rpc_username, rpc_password)

        def quota_probe() -> dict[str, int] | None:
            return cleanup._probe_remote_disk_usage_from_runtime(
                secret_paths,
                args.ssh_key,
                ssh_executable=args.ssh,
                ssh_keygen_executable=args.ssh_keygen,
                ssh_port=args.ssh_port,
            )

        result = run_guard_cycle(
            quota_probe,
            rpc,
            args.state_file,
            args.metrics_path,
            pause_at_bytes=args.pause_at_bytes,
            resume_below_bytes=args.resume_below_bytes,
        )
    except Exception:
        result = {"status": "runtime_unavailable"}
    print(json.dumps({"event": "seedbox_space_guard", **result}, sort_keys=True, separators=(",", ":")), flush=True)
    return 0 if result.get("status") == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
