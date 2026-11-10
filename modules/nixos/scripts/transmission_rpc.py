"""Read-only Transmission RPC transport and metadata normalization.

This module deliberately exposes no torrent-removal operation. File mapping is
not established here, so normalized file-safety facts remain false until a
separate verifier proves them.
"""

import json
import math
from numbers import Real
from typing import Any, Callable, Mapping
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPBasicAuthHandler, HTTPPasswordMgrWithDefaultRealm, Request, build_opener


BASE_TORRENT_FIELDS = (
    "id",
    "status",
    "secondsSeeding",
    "uploadRatio",
    "trackers",
    "files",
)


def torrent_fields_for_rpc_version(rpc_version: int) -> tuple[str, ...]:
    """Return torrent-get fields available in the documented RPC version."""
    if not isinstance(rpc_version, int) or isinstance(rpc_version, bool) or rpc_version < 1:
        raise TransmissionRPCError("Transmission RPC version is unavailable")
    fields = list(BASE_TORRENT_FIELDS)
    if rpc_version >= 4:
        fields.append("downloadDir")
    if rpc_version >= 5:
        fields.extend(("leftUntilDone", "percentDone"))
    if rpc_version >= 7:
        fields.append("trackerStats")
    else:
        fields.extend(("announceURL", "announceResponse"))
    if rpc_version >= 9:
        fields.append("isFinished")
    return tuple(fields)


class TransmissionRPCError(RuntimeError):
    """A safe RPC error that never includes response bodies or endpoint values."""


class TransmissionRPC:
    """Client for the read-only Transmission RPC operations used by retention."""

    def __init__(
        self,
        url: str,
        username: str,
        password: str,
        *,
        timeout: float = 20,
        tracker_classifier: Callable[[str], str] | None = None,
    ) -> None:
        parsed_url = urlsplit(url)
        if parsed_url.scheme != "https" or not parsed_url.netloc:
            raise ValueError("Transmission RPC endpoint must be an HTTPS URL")
        if parsed_url.username is not None or parsed_url.password is not None:
            raise ValueError("Transmission RPC endpoint must not embed credentials")
        if not isinstance(username, str) or not isinstance(password, str):
            raise ValueError("Transmission RPC credentials must be strings")

        self._url = url
        self._timeout = timeout
        self._session_id: str | None = None
        self._tracker_classifier = tracker_classifier or (lambda _host: "unknown")
        password_manager = HTTPPasswordMgrWithDefaultRealm()
        password_manager.add_password(None, url, username, password)
        self._opener = build_opener(HTTPBasicAuthHandler(password_manager))

    def _rpc(self, method: str, arguments: Mapping[str, Any] | None = None) -> dict[str, Any]:
        if method not in ("session-get", "torrent-get"):
            raise TransmissionRPCError("Transmission RPC operation is not allowed")
        request_arguments = dict(arguments or {})
        for _attempt in range(2):
            body = json.dumps({"method": method, "arguments": request_arguments}).encode("utf-8")
            headers = {"Content-Type": "application/json"}
            if self._session_id is not None:
                headers["X-Transmission-Session-Id"] = self._session_id
            request = Request(self._url, data=body, headers=headers, method="POST")
            try:
                with self._opener.open(request, timeout=self._timeout) as response:
                    payload = json.load(response)
            except HTTPError as error:
                session_id = error.headers.get("X-Transmission-Session-Id")
                status = error.code
                error.close()
                if status == 409 and session_id and session_id != self._session_id:
                    self._session_id = session_id
                    continue
                raise TransmissionRPCError("Transmission RPC request failed") from None
            except (URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError):
                raise TransmissionRPCError("Transmission RPC request failed") from None

            if not isinstance(payload, dict) or payload.get("result") != "success":
                raise TransmissionRPCError("Transmission RPC returned an unsuccessful response")
            result = payload.get("arguments")
            if not isinstance(result, dict):
                raise TransmissionRPCError("Transmission RPC response is malformed")
            return result

        raise TransmissionRPCError("Transmission RPC session negotiation failed")

    def get_session(self) -> dict[str, Any]:
        """Return the non-secret session metadata used to identify the RPC version."""
        return self._rpc("session-get")

    def get_torrents(self) -> list[dict[str, Any]]:
        """Fetch and normalize torrent state using only the documented get method."""
        session = self.get_session()
        fields = torrent_fields_for_rpc_version(session.get("rpc-version"))
        response = self._rpc("torrent-get", {"fields": list(fields)})
        torrents = response.get("torrents")
        if not isinstance(torrents, list):
            raise TransmissionRPCError("Transmission RPC torrent response is malformed")
        return [normalize_torrent(torrent, self._tracker_classifier) for torrent in torrents]


def _is_finite_number(value: Any) -> bool:
    if not isinstance(value, Real) or isinstance(value, bool):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def _tracker_details(torrent: Mapping[str, Any]) -> list[dict[str, Any]]:
    stats = torrent.get("trackerStats")
    if isinstance(stats, list):
        details = []
        for tracker in stats:
            if not isinstance(tracker, Mapping):
                details.append({"host": None, "announce_state": None})
                continue
            host = tracker.get("host")
            if not isinstance(host, str) or not host:
                host = None
            details.append({"host": host, "announce_state": tracker.get("announceState")})
        return details

    announce_url = torrent.get("announceURL")
    active_host = urlsplit(announce_url).hostname if isinstance(announce_url, str) else None
    announce_reported = bool(torrent.get("announceResponse"))
    legacy_trackers = torrent.get("trackers")
    details = []
    if isinstance(legacy_trackers, list):
        for tracker in legacy_trackers:
            if not isinstance(tracker, Mapping) or not isinstance(tracker.get("announce"), str):
                details.append({"host": None, "announce_state": None})
                continue
            host = urlsplit(tracker["announce"]).hostname
            details.append(
                {
                    "host": host,
                    "announce_state": (
                        "reported" if host == active_host and announce_reported else "not_reported"
                    ),
                }
            )
    if details:
        return details
    if not active_host:
        return []
    return [{"host": active_host, "announce_state": "reported" if announce_reported else "not_reported"}]


def normalize_torrent(
    torrent: Any,
    tracker_classifier: Callable[[str], str] | None = None,
) -> dict[str, Any]:
    """Normalize a Transmission torrent object into policy facts and safe metadata.

    Tracker classification is supplied by an explicit host classifier. Without
    one, every tracker is unknown. Local file facts are deliberately false: a
    separate path verifier must prove mapping, local equality, and ownership.
    """
    if not isinstance(torrent, Mapping):
        raise TransmissionRPCError("Transmission RPC torrent record is malformed")

    torrent_id = torrent.get("id")
    if not isinstance(torrent_id, int) or isinstance(torrent_id, bool):
        raise TransmissionRPCError("Transmission RPC torrent identifier is malformed")

    left_until_done = torrent.get("leftUntilDone")
    percent_done = torrent.get("percentDone")
    has_completion_facts = (
        isinstance(left_until_done, int)
        and not isinstance(left_until_done, bool)
        and left_until_done == 0
        and _is_finite_number(percent_done)
        and percent_done == 1.0
    )
    status = torrent.get("status")
    if "leftUntilDone" in torrent or "percentDone" in torrent:
        # isFinished describes a seeding stop condition, not download completion.
        complete = has_completion_facts
    else:
        complete = status == 6

    seeding_seconds = torrent.get("secondsSeeding")
    if not isinstance(seeding_seconds, int) or isinstance(seeding_seconds, bool) or seeding_seconds < 0:
        seeding_seconds = None

    torrent_ratio = torrent.get("uploadRatio")
    if not _is_finite_number(torrent_ratio):
        torrent_ratio = None

    tracker_details = _tracker_details(torrent)
    classifier = tracker_classifier or (lambda _host: "unknown")
    policy_trackers = []
    for tracker in tracker_details:
        host = tracker.get("host")
        if not isinstance(host, str) or not host:
            classification = "unknown"
        else:
            try:
                classification = classifier(host)
            except Exception:
                classification = "unknown"
        if classification not in ("public", "private"):
            classification = "unknown"
        policy_tracker: dict[str, Any] = {"classification": classification}
        if classification == "private":
            policy_tracker["ratio_source_available"] = False
        policy_trackers.append(policy_tracker)

    download_directory = torrent.get("downloadDir")
    if not isinstance(download_directory, str):
        download_directory = ""
    files = torrent.get("files")
    file_paths = []
    file_paths_valid = (
        isinstance(files, list)
        and bool(files)
        and all(
            isinstance(item, Mapping)
            and isinstance(item.get("name"), str)
            and bool(item.get("name"))
            and "\0" not in item["name"]
            for item in files
        )
    )
    if isinstance(files, list):
        file_paths = [item["name"] for item in files if isinstance(item, Mapping) and isinstance(item.get("name"), str)]

    return {
        "id": torrent_id,
        "candidate": {
            "complete": complete,
            "seeding_seconds": seeding_seconds,
            "torrent_ratio": torrent_ratio,
            "trackers": policy_trackers,
            "files": [
                {
                    "mapped": False,
                    "source_mapping_verified": False,
                    "source_identity": None,
                    "source_ownership_verified": False,
                    "source_owner_count": None,
                    "local_match": False,
                    "shared_safe": False,
                }
                for _path in file_paths
            ],
        },
        "tracker_states": tracker_details,
        "download_directory": download_directory,
        "file_paths": file_paths,
        "file_paths_valid": file_paths_valid,
    }
