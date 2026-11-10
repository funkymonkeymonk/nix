"""Reconcile Bazarr's connections to local Servarr services."""

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

from media_api_reconcile import ReconciliationError


def read_secret(path: str) -> str:
    try:
        value = pathlib.Path(path).read_text(encoding="utf-8").strip()
    except OSError as error:
        raise ReconciliationError("A configured runtime API-key file is unavailable") from error
    if not value:
        raise ReconciliationError("A configured runtime API-key file is empty")
    return value


def read_settings(base_url: str, api_key: str) -> dict[str, Any]:
    url = f"{base_url.rstrip('/')}/api/system/settings"
    request = urllib.request.Request(url, headers={"X-API-KEY": api_key, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise ReconciliationError(f"Bazarr API request failed with HTTP {error.code}") from error
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise ReconciliationError("Bazarr API request could not reach the local service") from error
    except json.JSONDecodeError as error:
        raise ReconciliationError("Bazarr API returned invalid JSON") from error
    if not isinstance(result, dict):
        raise ReconciliationError("Bazarr API returned an unsupported settings document")
    return result


def wait_for_settings(base_url: str, api_key: str, timeout_seconds: int = 60) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            return read_settings(base_url, api_key)
        except ReconciliationError:
            time.sleep(1)
    raise ReconciliationError("Bazarr API did not become ready before timeout")


def request_settings(base_url: str, api_key: str, settings: dict[str, str]) -> None:
    """Submit only managed Bazarr fields in the API's form-encoded format."""
    url = f"{base_url.rstrip('/')}/api/system/settings"
    request = urllib.request.Request(
        url,
        data=urllib.parse.urlencode(settings).encode("utf-8"),
        headers={
            "X-API-KEY": api_key,
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20):
            return
    except urllib.error.HTTPError as error:
        raise ReconciliationError(f"Bazarr API request failed with HTTP {error.code}") from error
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise ReconciliationError("Bazarr API request could not reach the local service") from error


def _same_value(current: Any, wanted: str, field: str) -> bool:
    if field == "base_url":
        return str(current or "").strip("/") == wanted.strip("/")
    if wanted in {"true", "false"}:
        return str(current).lower() == wanted
    return str(current) == wanted


def _connection_fields(service: str, config: dict[str, Any]) -> dict[str, str]:
    parsed = urllib.parse.urlsplit(config["baseUrl"])
    if not parsed.hostname:
        raise ReconciliationError(f"The configured {service} URL is invalid")
    api_key = read_secret(config["apiKeyFile"])
    prefix = f"settings-{service}-"
    fields = {
        f"{prefix}ip": parsed.hostname,
        f"{prefix}port": str(parsed.port or (443 if parsed.scheme == "https" else 80)),
        f"{prefix}base_url": parsed.path.rstrip("/"),
        f"{prefix}ssl": str(parsed.scheme == "https").lower(),
        f"{prefix}apikey": api_key,
    }
    return fields


def reconcile(config: dict[str, Any]) -> None:
    bazarr_api_key = read_secret(config["bazarrApiKeyFile"])
    current = wait_for_settings(config["bazarrBaseUrl"], bazarr_api_key)
    desired = {
        "settings-general-base_url": "",
        "settings-general-use_sonarr": str(config.get("useSonarr", False)).lower(),
        "settings-general-use_radarr": str(config.get("useRadarr", False)).lower(),
    }

    for service in ("sonarr", "radarr"):
        service_config = config.get(service)
        if service_config is not None:
            desired.update(_connection_fields(service, service_config))

    changes = {}
    for form_key, wanted in desired.items():
        parts = form_key.split("-", 2)
        if len(parts) != 3 or parts[0] != "settings":
            raise ReconciliationError("Bazarr setting key has an unsupported format")
        section, field = parts[1], parts[2]
        current_section = current.get(section, {})
        if not isinstance(current_section, dict) or not _same_value(current_section.get(field), wanted, field):
            changes[form_key] = wanted

    if changes:
        request_settings(config["bazarrBaseUrl"], bazarr_api_key, changes)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        reconcile(json.loads(args.config.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ReconciliationError) as error:
        print(f"Bazarr reconciliation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
