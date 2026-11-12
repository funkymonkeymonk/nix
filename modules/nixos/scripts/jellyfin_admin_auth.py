"""Verify that the declared Jellyfin credentials belong to an administrator."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from media_api_reconcile import ReconciliationError, open_local_url


CLIENT = 'MediaBrowser Client="Drlight NixOS Auth Check", Device="Drlight", DeviceId="drlight-nixos-admin-auth-check", Version="1"'


class JellyfinRetryableError(ReconciliationError):
    """The local Jellyfin server is not ready to answer API requests yet."""


def _read_secret(path: str) -> str:
    try:
        value = pathlib.Path(path).read_text(encoding="utf-8").strip()
    except OSError as error:
        raise ReconciliationError("A configured Jellyfin credential file is unavailable") from error
    if not value:
        raise ReconciliationError("A configured Jellyfin credential file is empty")
    return value


def _request_json(
    base_url: str,
    endpoint: str,
    authorization: str,
    method: str = "GET",
    payload: dict[str, str] | None = None,
) -> dict[str, Any]:
    headers = {"Accept": "application/json", "Authorization": authorization}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/{endpoint.lstrip('/')}",
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with open_local_url(request) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        if status == 503:
            raise JellyfinRetryableError("Jellyfin API is not ready yet") from error
        raise ReconciliationError(f"Jellyfin API request failed with HTTP {status}") from error
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise JellyfinRetryableError("Jellyfin API request could not reach the local service") from error

    try:
        result = json.loads(body.decode("utf-8")) if body else {}
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReconciliationError("Jellyfin API returned invalid JSON") from error
    if not isinstance(result, dict):
        raise ReconciliationError("Jellyfin API returned an unsupported response")
    return result


def _request_when_ready(
    base_url: str,
    endpoint: str,
    authorization: str,
    method: str = "GET",
    payload: dict[str, str] | None = None,
    timeout_seconds: int = 60,
) -> dict[str, Any]:
    """Retry transient connection failures while Jellyfin finishes starting."""
    deadline = time.monotonic() + timeout_seconds
    last_error: JellyfinRetryableError | None = None
    while True:
        try:
            return _request_json(base_url, endpoint, authorization, method, payload)
        except JellyfinRetryableError as error:
            last_error = error

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ReconciliationError("Jellyfin API did not become ready before the timeout") from last_error
        time.sleep(min(1, remaining))


def wait_for_server(base_url: str) -> None:
    """Wait briefly for Jellyfin's public API to become ready after service start."""
    _request_when_ready(base_url, "System/Info/Public", CLIENT)


def verify_admin(config: dict[str, Any]) -> None:
    """Authenticate with runtime credentials and require administrator policy."""
    base_url = config["baseUrl"].rstrip("/")
    parsed = urllib.parse.urlsplit(base_url)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise ReconciliationError("Jellyfin credential verification is restricted to loopback HTTP")

    username = _read_secret(config["usernameFile"])
    password = _read_secret(config["passwordFile"])
    wait_for_server(base_url)
    login = _request_when_ready(
        base_url,
        "Users/AuthenticateByName",
        CLIENT,
        method="POST",
        payload={"Username": username, "Pw": password},
    )
    token = login.get("AccessToken") or login.get("accessToken")
    if not isinstance(token, str) or not token:
        raise ReconciliationError("Jellyfin did not return an authenticated session")

    current_client = f'{CLIENT}, Token="{token}"'
    user = _request_when_ready(base_url, "Users/Me", current_client)
    policy = user.get("Policy") or user.get("policy") or {}
    is_admin = policy.get("IsAdministrator", policy.get("isAdministrator", False))
    if is_admin is not True:
        raise ReconciliationError("Configured Jellyfin account is not an administrator")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        config = json.loads(args.config.read_text(encoding="utf-8"))
        verify_admin(config)
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ReconciliationError) as error:
        print(f"Jellyfin admin verification failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
