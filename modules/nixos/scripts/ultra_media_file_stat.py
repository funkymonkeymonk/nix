"""Strict, read-only remote file metadata over the configured SSH transport."""

import calendar
import posixpath
import re
import shlex
import subprocess
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Any, Callable, Mapping, Sequence


_APP_STATS_DISK_ROW_PATTERN = re.compile(
    r"^\s*\d+\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}"
    r"(?:\.\d+)?\s+(?P<used_gb>[\d,]+(?:\.\d+)?)\s*$"
)

_REMOTE_STAT_PATTERN = re.compile(
    r"(?P<kind>[^\t]+)\t(?P<size>\d+)\t"
    r"(?P<date>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})"
    r"(?:\.(?P<fraction>\d{1,9}))? (?P<zone>[+-]\d{4})"
)


def parse_remote_stat(output: str) -> dict[str, Any] | None:
    """Parse GNU stat output without retaining or logging source paths."""
    if not isinstance(output, str):
        return None
    match = _REMOTE_STAT_PATTERN.fullmatch(output.strip())
    if match is None or match.group("kind") != "regular file":
        return None
    try:
        size = int(match.group("size"))
        instant = datetime.strptime(
            f"{match.group('date')} {match.group('zone')}",
            "%Y-%m-%d %H:%M:%S %z",
        )
        seconds = calendar.timegm(instant.utctimetuple())
        fraction = (match.group("fraction") or "").ljust(9, "0")
        mtime_ns = seconds * 1_000_000_000 + (int(fraction) if fraction else 0)
    except (OverflowError, ValueError):
        return None
    if size < 0:
        return None
    return {"regular_file": True, "size": size, "mtime_ns": mtime_ns}


def parse_app_stats_disk_usage(output: str) -> dict[str, int] | None:
    """Parse the last Ultra app-stats disk row as decimal bytes."""
    if not isinstance(output, str):
        return None
    used_gigabytes = None
    for line in output.splitlines():
        match = _APP_STATS_DISK_ROW_PATTERN.fullmatch(line)
        if match is None:
            continue
        try:
            value = Decimal(match.group("used_gb").replace(",", ""))
        except InvalidOperation:
            continue
        if not value.is_finite() or value < 0:
            continue
        used_gigabytes = value
    if used_gigabytes is None:
        return None
    try:
        return {"used_bytes": int(used_gigabytes * Decimal(1_000_000_000))}
    except (OverflowError, ValueError):
        return None


def make_remote_disk_usage_probe(
    ssh_arguments: Sequence[str],
    ssh_username: str,
    ssh_host: str,
    *,
    process_runner: Callable[..., Any] = subprocess.run,
) -> Callable[[], dict[str, int] | None]:
    """Create a strict-SSH probe for Ultra's account-level disk usage."""
    if (
        not isinstance(ssh_arguments, Sequence)
        or isinstance(ssh_arguments, (str, bytes))
        or not ssh_arguments
        or not isinstance(ssh_username, str)
        or not ssh_username
        or any(character.isspace() or character in "\0@:" for character in ssh_username)
        or not isinstance(ssh_host, str)
        or not ssh_host
        or any(character.isspace() or character in "\0@:" for character in ssh_host)
    ):
        raise ValueError("ssh_config_missing")
    target = f"{ssh_username}@{ssh_host}"
    command = "app-stats show -s disk -t hour -c 1"

    def probe() -> dict[str, int] | None:
        try:
            result = process_runner(
                [*ssh_arguments, target, command],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                check=True,
                timeout=30,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        if getattr(result, "returncode", 0) != 0:
            return None
        return parse_app_stats_disk_usage(result.stdout)

    return probe


def make_remote_source_stat(
    ssh_arguments: Sequence[str],
    ssh_username: str,
    ssh_host: str,
    *,
    process_runner: Callable[..., Any] = subprocess.run,
) -> Callable[[str], Mapping[str, Any] | None]:
    """Create a strict-SSH stat probe that never interprets source paths as shell."""
    if (
        not isinstance(ssh_arguments, Sequence)
        or isinstance(ssh_arguments, (str, bytes))
        or not ssh_arguments
        or not isinstance(ssh_username, str)
        or not ssh_username
        or any(character.isspace() or character in "\0@:" for character in ssh_username)
        or not isinstance(ssh_host, str)
        or not ssh_host
        or any(character.isspace() or character in "\0@:" for character in ssh_host)
    ):
        raise ValueError("ssh_config_missing")
    target = f"{ssh_username}@{ssh_host}"

    def source_stat(remote_path: str) -> Mapping[str, Any] | None:
        if (
            not isinstance(remote_path, str)
            or not remote_path.startswith("/")
            or "\0" in remote_path
            or ".." in remote_path.split("/")
        ):
            return None
        normalized_path = posixpath.normpath(remote_path)
        command = (
            "LC_ALL=C stat --printf="
            + shlex.quote("%F\\t%s\\t%y\\n")
            + " -- "
            + shlex.quote(normalized_path)
        )
        try:
            result = process_runner(
                [*ssh_arguments, target, command],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                check=True,
                timeout=20,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        return parse_remote_stat(result.stdout)

    return source_stat
