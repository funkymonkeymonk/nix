"""Read-only Arr and Jellyfin status collection for the media sync snapshot."""

from __future__ import annotations

import argparse
import json
import re
import urllib.error
import urllib.parse
import urllib.request
from enum import IntEnum
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence


class Status(IntEnum):
    NO = 0
    YES = 1
    UNKNOWN = -1
    FAILED = -2


def normalize_title(value: str) -> str:
    """Normalize presentation punctuation without lossy substring matching."""
    return re.sub(r"\s+", " ", re.sub(r"[^\w\s]", " ", value, flags=re.UNICODE)).strip().casefold()


def _read_secret(path: str) -> str:
    return Path(path).read_text(encoding="utf-8").strip()


def _http_json(
    url: str,
    *,
    method: str = "GET",
    headers: Mapping[str, str] | None = None,
    body: Mapping[str, Any] | None = None,
    timeout: float = 5.0,
) -> Any:
    payload = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(url, data=payload, method=method, headers=dict(headers or {}))
    if body is not None:
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


Request = Callable[..., Any]


class ArrClient:
    def __init__(self, base_url: str, api_key: str, *, request: Request = _http_json) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key
        self.request = request

    def import_status(self, download_id: str) -> Status:
        try:
            imported = False
            page = 1
            records_read = 0
            while True:
                query = urllib.parse.urlencode(
                    {"downloadId": download_id, "page": str(page), "pageSize": "100"}
                )
                payload = self.request(
                    f"{self.base_url}/history?{query}",
                    headers={"X-Api-Key": self.api_key},
                    timeout=5.0,
                )
                if not isinstance(payload, Mapping) or not isinstance(payload.get("records"), list):
                    return Status.UNKNOWN
                records = payload["records"]
                records_read += len(records)
                failed = False
                for record in records:
                    if not isinstance(record, Mapping):
                        continue
                    if str(record.get("downloadId", "")) != download_id:
                        continue
                    event_type = str(record.get("eventType", "")).casefold()
                    if event_type == "downloadfolderimported":
                        imported = True
                    elif event_type == "downloadfailedimport":
                        failed = True
                if failed:
                    return Status.FAILED
                total_records = payload.get("totalRecords")
                if (
                    not records
                    or not isinstance(total_records, int)
                    or isinstance(total_records, bool)
                    or records_read >= total_records
                ):
                    break
                page += 1
            if imported:
                return Status.YES
            return Status.NO
        except (OSError, ValueError, TypeError, KeyError, urllib.error.URLError):
            return Status.UNKNOWN


class JellyfinClient:
    def __init__(
        self,
        base_url: str,
        username: str,
        password: str,
        *,
        request: Request = _http_json,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.username = username
        self.password = password
        self.request = request
        self._items_cache: list[Mapping[str, Any]] | None = None

    def _items(self) -> list[Mapping[str, Any]]:
        auth = self.request(
            f"{self.base_url}/Users/AuthenticateByName",
            method="POST",
            body={"Username": self.username, "Pw": self.password},
            headers={"X-Emby-Authorization": 'MediaBrowser Client="ultra-media-sync", Device="drlight"'},
            timeout=5.0,
        )
        token = auth.get("AccessToken") if isinstance(auth, Mapping) else None
        if not isinstance(token, str) or not token:
            raise ValueError("jellyfin_authentication_failed")
        payload = self.request(
            f"{self.base_url}/Items?Recursive=true&Fields=Name&Limit=10000",
            headers={"X-Emby-Token": token},
            timeout=5.0,
        )
        if not isinstance(payload, Mapping) or not isinstance(payload.get("Items"), list):
            raise ValueError("jellyfin_items_invalid")
        return [item for item in payload["Items"] if isinstance(item, Mapping)]

    def title_status(self, title: str) -> Status:
        try:
            expected = normalize_title(title)
            if not expected:
                return Status.NO
            if self._items_cache is None:
                self._items_cache = self._items()
            return Status.YES if any(
                normalize_title(item.get("Name", "")) == expected for item in self._items_cache
            ) else Status.NO
        except (OSError, ValueError, TypeError, KeyError, urllib.error.URLError):
            return Status.UNKNOWN


def collect_statuses(
    torrents: Sequence[Mapping[str, Any]],
    *,
    arr_clients: Sequence[ArrClient],
    jellyfin_client: JellyfinClient,
) -> dict[str, tuple[Status, Status]]:
    """Return status by opaque torrent id; failures are represented as UNKNOWN."""
    statuses: dict[str, tuple[Status, Status]] = {}
    for torrent in torrents:
        torrent_id = str(torrent.get("id", ""))
        download_id = torrent.get("download_id")
        arr = Status.UNKNOWN
        if isinstance(download_id, str) and re.fullmatch(r"[0-9a-fA-F]{40}", download_id):
            client_results = [client.import_status(download_id) for client in arr_clients]
            if any(result is Status.UNKNOWN for result in client_results):
                arr = Status.UNKNOWN
            elif any(result is Status.FAILED for result in client_results):
                arr = Status.NO
            elif any(result is Status.YES for result in client_results):
                arr = Status.YES
            else:
                arr = Status.NO
        jellyfin = jellyfin_client.title_status(str(torrent.get("title", "")))
        statuses[torrent_id] = (arr, jellyfin)
    return statuses


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", action="append", default=[])
    parser.parse_args(argv)
    return 0
