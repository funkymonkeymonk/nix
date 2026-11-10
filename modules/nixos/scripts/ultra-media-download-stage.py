"""Copy completed Transmission payloads into Drlight's non-library stage.

The only remote operations are Transmission's session-get/torrent-get and
read-only rsync copies. Runtime configuration and logs deliberately exclude
per-torrent and remote-path details.
"""

import argparse
import fcntl
import ipaddress
import json
import os
import posixpath
import shlex
import stat
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Callable, Iterator, Mapping, Sequence
from urllib.parse import urlsplit


STAGING_ROOT = "/srv/media/.arr-staging"


@contextmanager
def _operation_lock(staging_root: str | Path = STAGING_ROOT) -> Iterator[None]:
    """Serialize staging against report-only cleanup using one lock file."""
    root = Path(staging_root).absolute()
    root.mkdir(parents=True, exist_ok=True)
    if root.is_symlink():
        raise OSError("staging root must not be a symbolic link")
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
        f"--rsh={ssh_command}",
        remote_source,
        local_destination,
    ]


def stage_completed_downloads(
    torrents: Sequence[Mapping[str, Any]],
    mappings: Any,
    transfer: Callable[[str, Path], None],
    *,
    staging_root: str | Path = STAGING_ROOT,
) -> dict[str, int]:
    """Copy only completed, fully mapped torrents and publish atomically per torrent.

    Transfer callbacks receive a remote payload path and a private temporary
    local target. They must perform copy-only transfers and leave remote data
    untouched. Per-torrent names and paths are intentionally absent from the
    returned aggregate counts.
    """
    normalized_mappings = _validate_normalized_mappings(mappings)
    configured_root = Path(staging_root).absolute()
    configured_root.mkdir(parents=True, exist_ok=True)
    if configured_root.is_symlink():
        raise OSError("staging root must not be a symbolic link")
    root = configured_root.resolve()

    result = {
        "completed_candidates": 0,
        "staged": 0,
        "skipped_incomplete": 0,
        "skipped_unknown_path": 0,
        "skipped_malformed_path": 0,
        "failed": 0,
    }

    for torrent in torrents:
        candidate = normalize_transmission_source_mappings(
            torrent, normalized_mappings, staging_root=str(root)
        )
        if candidate.get("complete") is not True:
            result["skipped_incomplete"] += 1
            continue
        result["completed_candidates"] += 1

        paths = torrent.get("file_paths")
        download_directory = torrent.get("download_directory")
        if (
            torrent.get("file_paths_valid") is not True
            or not isinstance(paths, list)
            or not paths
            or not isinstance(download_directory, str)
        ):
            result["skipped_malformed_path"] += 1
            continue

        source_files = candidate.get("files")
        if not isinstance(source_files, list) or len(source_files) != len(paths):
            result["skipped_malformed_path"] += 1
            continue

        transfers: list[tuple[str, Path]] = []
        seen_destinations: set[str] = set()
        reason: str | None = None
        for index, file_path in enumerate(paths):
            try:
                remote_source = posixpath.normpath(
                    posixpath.join(
                        _normalize_absolute_remote_path(download_directory),
                        _normalize_relative_path(file_path),
                    )
                )
                local_destination = map_remote_path_to_staging(
                    download_directory,
                    file_path,
                    normalized_mappings,
                    staging_root=str(root),
                )
                if source_files[index].get("source_mapping_verified") is not True:
                    reason = "malformed_path"
                    break
            except StagingConfigurationError as error:
                reason = error.reason
                break
            if local_destination in seen_destinations:
                reason = "malformed_path"
                break
            seen_destinations.add(local_destination)
            transfers.append((remote_source, Path(local_destination)))

        if reason == "unknown_path":
            result["skipped_unknown_path"] += 1
            continue
        if reason is not None or not transfers:
            result["skipped_malformed_path"] += 1
            continue

        temporary_directory = Path(tempfile.mkdtemp(prefix=".incoming-", dir=root))
        staged_files: list[tuple[Path, Path]] = []
        try:
            for index, (remote_source, local_destination) in enumerate(transfers):
                temporary_file = temporary_directory / f"payload-{index}"
                transfer(remote_source, temporary_file)
                if not temporary_file.is_file():
                    raise OSError("transfer did not produce a regular payload")
                staged_files.append((temporary_file, local_destination))

            backups: list[tuple[Path, Path]] = []
            published: list[Path] = []
            try:
                for index, (temporary_file, local_destination) in enumerate(staged_files):
                    local_destination.parent.mkdir(parents=True, exist_ok=True)
                    resolved_parent = local_destination.parent.resolve()
                    if os.path.commonpath((str(root), str(resolved_parent))) != str(root):
                        raise OSError("staging destination escapes the staging root")
                    if local_destination.exists():
                        if not local_destination.is_file():
                            raise OSError("staging destination is not a regular file")
                        backup = temporary_directory / f"backup-{index}"
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
            result["staged"] += 1
        except (OSError, subprocess.SubprocessError):
            result["failed"] += 1
        finally:
            for item in temporary_directory.iterdir():
                if item.is_dir() and not item.is_symlink():
                    import shutil

                    shutil.rmtree(item)
                else:
                    item.unlink(missing_ok=True)
            temporary_directory.rmdir()

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
    staging_root: str | Path = STAGING_ROOT,
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

        try:
            from transmission_rpc import TransmissionRPC

            rpc = TransmissionRPC(rpc_url, rpc_username, rpc_password)
            torrents = rpc.get_torrents()
        except Exception:
            raise StagingConfigurationError("rpc_unavailable") from None

        def transfer(remote_source: str, local_temporary: Path) -> None:
            remote = f"{ssh_username}@{host}:{remote_source}"
            arguments = build_rsync_arguments(
                rsync_executable, ssh_command, remote, str(local_temporary)
            )
            process_runner(
                arguments,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=True,
            )

        return stage_completed_downloads(
            torrents, mappings, transfer, staging_root=staging_root
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
    args = parser.parse_args(argv)
    if not args.stage_downloads:
        print("staging failed reason=operation_required", file=sys.stderr)
        return 2

    try:
        with _operation_lock():
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
            )
    except StagingConfigurationError as error:
        print(f"staging failed reason={error.reason}", file=sys.stderr)
        return 1
    except (OSError, subprocess.SubprocessError):
        print("staging failed reason=local_io_failure", file=sys.stderr)
        return 1

    print("staging " + " ".join(f"{name}={count}" for name, count in result.items()))
    return 1 if result["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
