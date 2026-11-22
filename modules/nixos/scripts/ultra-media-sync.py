"""Run Drlight staging followed by retention-eligible seedbox cleanup.

The staging and cleanup steps share a systemd job. Cleanup is called only
after staging returns; per-torrent receipts authorize only fully published
copies, while individual transfer failures remain isolated.
"""

import argparse
import importlib.util
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Callable, Mapping


_CLEANUP_OPERATION_FAILURE_REASONS = {
    "torrent_revalidation_unavailable",
    "torrent_revalidation_failed",
    "transmission_remove_failed",
}

_REASON_CODES = {
    "credential_unavailable",
    "download_root_malformed",
    "download_root_missing",
    "download_mapping_ambiguous",
    "download_mapping_malformed",
    "download_mappings_missing",
    "download_root_unsafe",
    "rpc_password_missing",
    "rpc_unavailable",
    "rpc_url_insecure",
    "rpc_url_malformed",
    "rpc_url_missing",
    "rpc_username_missing",
    "runtime_configuration_unavailable",
    "runtime_dependency_unavailable",
    "ssh_config_missing",
    "ssh_host_key_unavailable",
    "ssh_key_unavailable",
    "staging_root_unavailable",
    "malformed_path",
    "unknown_path",
    "transmission_state_unavailable",
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


def _emit_json(event: Mapping[str, Any]) -> None:
    print(json.dumps(dict(event), sort_keys=True, separators=(",", ":")), flush=True)


def _count(report: Mapping[str, Any], field: str) -> int:
    value = report.get(field)
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else 0


def _total(report: Mapping[str, Any], field: str) -> int | None:
    value = report.get(field)
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else None


def _safe_reasons(value: Any) -> dict[str, int]:
    if not isinstance(value, Mapping):
        return {}
    return {
        reason: count
        for reason, count in sorted(value.items())
        if isinstance(reason, str)
        and re.fullmatch(r"[a-z][a-z0-9_]*", reason)
        and isinstance(count, int)
        and not isinstance(count, bool)
        and count >= 0
    }


def run_sync_cycle(
    stage_runner: Callable[[], Mapping[str, Any]],
    cleanup_runner: Callable[[], Mapping[str, Any]],
) -> dict[str, Any]:
    """Run staging before cleanup and return a privacy-safe aggregate summary."""
    stage_result = stage_runner()
    if not isinstance(stage_result, Mapping):
        raise RuntimeError("staging_result_unavailable")
    if stage_result.get("status") == "busy":
        return {
            "staging": dict(stage_result),
            "cleanup": {"mode": "skipped"},
            "summary": {
                "event": "sync_run_summary",
                "staging_status": "busy",
                "cleanup_status": "skipped",
                "run_status": "busy",
            },
        }
    cleanup_result = cleanup_runner()
    if not isinstance(cleanup_result, Mapping):
        raise RuntimeError("cleanup_result_unavailable")

    staged_failed = _count(stage_result, "failed")
    cleanup_reasons = _safe_reasons(cleanup_result.get("reasons"))
    cleanup_operation_failed = any(
        cleanup_reasons.get(reason, 0) > 0
        for reason in _CLEANUP_OPERATION_FAILURE_REASONS
    )
    cleanup_status = (
        "disabled"
        if cleanup_result.get("mode") == "disabled"
        else "failed"
        if cleanup_operation_failed
        else "blocked"
        if _count(cleanup_result, "blocked") > 0
        else "complete"
    )
    summary = {
        "event": "sync_run_summary",
        "staging_status": "partial" if staged_failed else "complete",
        "cleanup_status": cleanup_status,
        "run_status": "failed" if staged_failed or cleanup_operation_failed else "complete",
        "torrents_total": _total(stage_result, "torrents_total"),
        "torrents_staged": _count(stage_result, "staged"),
        "files_total": _total(stage_result, "files_total"),
        "bytes_total": _total(stage_result, "bytes_total"),
        "torrents_failed": staged_failed,
        "files_transferred": _count(stage_result, "files_transferred"),
        "files_reused": _count(stage_result, "files_reused"),
        "bytes_transferred": _count(stage_result, "bytes_transferred"),
        "bytes_reused": _count(stage_result, "bytes_reused"),
        "receipts_created": _count(stage_result, "receipts_created"),
        "cleanup_mode": cleanup_result.get("mode", "unknown"),
        "cleanup_candidates": _count(cleanup_result, "candidates"),
        "cleanup_removed": _count(cleanup_result, "removed"),
        "cleanup_blocked": _count(cleanup_result, "blocked"),
        "pending_after_run": _count(cleanup_result, "pending_after_run"),
        "cleanup_reasons": cleanup_reasons,
    }
    return {
        "staging": dict(stage_result),
        "cleanup": dict(cleanup_result),
        "summary": summary,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
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
    parser.add_argument("--queue-root", default="/var/lib/ultra-media/cleanup-queue")
    parser.add_argument("--metrics-path", default="/run/ultra-media-metrics/ultra-media-sync.prom")
    parser.add_argument("--radarr-url")
    parser.add_argument("--sonarr-url")
    parser.add_argument("--lidarr-url")
    parser.add_argument("--jellyfin-url")
    parser.add_argument("--radarr-api-key-file")
    parser.add_argument("--sonarr-api-key-file")
    parser.add_argument("--lidarr-api-key-file")
    parser.add_argument("--jellyfin-username-file")
    parser.add_argument("--jellyfin-password-file")
    parser.add_argument("--cleanup-enabled", action="store_true")
    parser.add_argument("--private-tracker-ratio-protection", action="store_true")
    parser.add_argument("--remote-disk-monitoring", action="store_true")
    parser.add_argument("--remote-disk-capacity-bytes", type=int, default=4_000_000_000_000)
    parser.add_argument("--remote-disk-warning-threshold-bytes", type=int, default=3_000_000_000_000)
    parser.add_argument(
        "--remote-disk-metrics-path",
        default="/run/ultra-media-metrics/ultra-seedbox.prom",
    )
    args = parser.parse_args(argv)

    secret_paths = {
        "rpc_url": args.rpc_url,
        "download_root": args.download_root,
        "ssh_host": args.ssh_host,
        "ssh_username": args.ssh_username,
        "known_hosts": args.known_hosts,
        "rpc_username": args.rpc_username,
        "rpc_password": args.rpc_password,
        "radarr_api_key": args.radarr_api_key_file,
        "sonarr_api_key": args.sonarr_api_key_file,
        "lidarr_api_key": args.lidarr_api_key_file,
        "jellyfin_username": args.jellyfin_username_file,
        "jellyfin_password": args.jellyfin_password_file,
    }
    phase = "staging"
    try:
        staging = _load_runtime_module(
            "ultra_media_download_stage", "ultra-media-download-stage.py"
        )
        cleanup = _load_runtime_module(
            "ultra_media_cleanup", "ultra-media-cleanup.py"
        )

        def run_stage() -> Mapping[str, Any]:
            result = staging._stage_from_runtime_files(
                secret_paths,
                args.ssh_key,
                ssh_port=args.ssh_port,
                ssh_executable=args.ssh,
                ssh_keygen_executable=args.ssh_keygen,
                rsync_executable=args.rsync,
                runtime_root=staging.RUNTIME_ROOT,
                cleanup_queue_root=args.queue_root if args.cleanup_enabled else None,
                metrics_path=args.metrics_path,
                library_status_config={
                    key: value
                    for key, value in {
                        "radarr_url": args.radarr_url,
                        "sonarr_url": args.sonarr_url,
                        "lidarr_url": args.lidarr_url,
                        "jellyfin_url": args.jellyfin_url,
                    }.items()
                    if value
                },
            )
            _emit_json({"event": "staging_run_result", **result})
            return result

        def run_cleanup() -> Mapping[str, Any]:
            nonlocal phase
            phase = "cleanup"
            if not args.cleanup_enabled:
                return {"mode": "disabled", "candidates": 0, "removed": 0, "blocked": 0}
            if args.remote_disk_monitoring:
                if (
                    args.remote_disk_capacity_bytes <= 0
                    or args.remote_disk_warning_threshold_bytes <= 0
                    or args.remote_disk_warning_threshold_bytes > args.remote_disk_capacity_bytes
                ):
                    raise RuntimeError("runtime_configuration_unavailable")
                _emit_json(cleanup._collect_remote_disk_usage(args))
            report = cleanup.run_runtime_cleanup(
                secret_paths,
                args.ssh_key,
                ssh_executable=args.ssh,
                ssh_keygen_executable=args.ssh_keygen,
                ssh_port=args.ssh_port,
                apply=True,
                private_tracker_ratio_protection=args.private_tracker_ratio_protection,
                queue_root=args.queue_root,
                runtime_root=staging.RUNTIME_ROOT,
            )
            _emit_json({"event": "cleanup_queue_summary", **report})
            return report

        result = run_sync_cycle(run_stage, run_cleanup)
        _emit_json(result["summary"])
        return 1 if result["summary"]["run_status"] == "failed" else 0
    except OSError:
        _emit_json(
            {"event": "sync_run_failed", "phase": phase, "reason": "local_io_failure"}
        )
        return 1
    except Exception as error:
        reason = getattr(error, "reason", None)
        if not isinstance(reason, str) or reason not in _REASON_CODES:
            reason = str(error)
        if not isinstance(reason, str) or reason not in _REASON_CODES:
            reason = f"{phase}_failed"
        _emit_json({"event": "sync_run_failed", "phase": phase, "reason": reason})
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
