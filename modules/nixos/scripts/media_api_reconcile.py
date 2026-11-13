"""Small, conservative HTTP primitives for media application reconcilers."""

from __future__ import annotations

import json
import pathlib
import urllib.error
import time
import urllib.request
import xml.etree.ElementTree as ElementTree
from typing import Any


class ReconciliationError(RuntimeError):
    """A safe-to-log reconciliation failure."""


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, new_url):
        return None


def open_local_url(request: urllib.request.Request, timeout: int = 20):
    """Open a local application request without proxies or cross-host redirects."""
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}),
        _NoRedirectHandler(),
    )
    return opener.open(request, timeout=timeout)


def expand_runtime_secrets(value: Any) -> Any:
    """Replace {"secret": "/absolute/path"} values at runtime only."""
    if isinstance(value, dict):
        if set(value) == {"secret"}:
            secret_path = pathlib.Path(value["secret"])
            try:
                return secret_path.read_text(encoding="utf-8").strip()
            except OSError as error:
                raise ReconciliationError("A configured runtime secret file is unavailable") from error
        return {key: expand_runtime_secrets(child) for key, child in value.items()}
    if isinstance(value, list):
        return [expand_runtime_secrets(child) for child in value]
    return value


def read_arr_api_key(config_xml: str) -> str:
    """Read an Arr API key from the service-owned config.xml."""
    try:
        root = ElementTree.parse(config_xml).getroot()
    except (OSError, ElementTree.ParseError) as error:
        raise ReconciliationError("Unable to read the Arr API configuration") from error

    for element in root.iter():
        if element.tag.casefold() == "apikey" and element.text:
            api_key = element.text.strip()
            if api_key:
                return api_key
    raise ReconciliationError("The Arr API key is missing from config.xml")


def request_json(
    base_url: str,
    api_key: str,
    endpoint: str,
    method: str = "GET",
    payload: Any | None = None,
) -> Any:
    """Call an Arr API without including credentials or response bodies in errors."""
    url = f"{base_url.rstrip('/')}/{endpoint.lstrip('/')}"
    headers = {"X-Api-Key": api_key, "Accept": "application/json"}
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with open_local_url(request) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        raise ReconciliationError(f"Arr API request failed with HTTP {status}") from error
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise ReconciliationError("Arr API request could not reach the local service") from error

    if not body:
        return {}
    try:
        return json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReconciliationError("Arr API returned invalid JSON") from error


def wait_for_arr_api(base_url: str, api_key: str, timeout_seconds: int = 60) -> None:
    """Wait for the local Arr HTTP API to become responsive after process start."""
    deadline = time.monotonic() + timeout_seconds
    last_error: ReconciliationError | None = None
    while time.monotonic() < deadline:
        try:
            request_json(base_url, api_key, "system/status")
            return
        except ReconciliationError as error:
            last_error = error
            time.sleep(1)
    raise ReconciliationError("Local Arr API did not become ready before timeout") from last_error


def unique_match(items: list[dict[str, Any]], predicate, description: str):
    matches = [item for item in items if predicate(item)]
    if len(matches) > 1:
        raise ReconciliationError(f"Managed {description} identity is ambiguous")
    return matches[0] if matches else None


def merge_fields(existing: list[dict[str, Any]], desired: dict[str, Any], description: str):
    """Apply named field values while preserving all unmanaged fields."""
    values = dict(desired)
    result = []
    found = set()
    for field in existing:
        item = dict(field)
        name = item.get("name")
        if name in values:
            item["value"] = values[name]
            found.add(name)
        result.append(item)
    missing = set(values) - found
    if missing:
        names = ", ".join(sorted(missing))
        raise ReconciliationError(f"{description} schema is missing declared fields: {names}")
    return result


def upsert_download_client(
    base_url: str,
    api_key: str,
    client_config: dict[str, Any],
) -> None:
    endpoint = "downloadclient"
    name = client_config["name"]
    implementation = client_config["implementation"]
    current = request_json(base_url, api_key, endpoint)
    existing = unique_match(
        current,
        lambda item: str(item.get("name", "")).casefold() == name.casefold(),
        f"download client '{name}'",
    )

    if existing is None:
        schemas = request_json(base_url, api_key, f"{endpoint}/schema")
        schema = unique_match(
            schemas,
            lambda item: item.get("implementation") == implementation,
            f"download-client schema '{implementation}'",
        )
        if schema is None:
            raise ReconciliationError(f"No download-client schema is available for '{implementation}'")
        desired = dict(schema)
        desired["name"] = name
        desired["implementation"] = implementation
        desired["enable"] = client_config.get("enable", True)
        desired["fields"] = merge_fields(schema.get("fields", []), client_config["fields"], "Download-client")
        request_json(base_url, api_key, endpoint, "POST", desired)
        return

    if existing.get("implementation") != implementation:
        raise ReconciliationError(
            f"Managed download client '{name}' has a different implementation; remove or rename it manually"
        )

    desired = dict(existing)
    desired["enable"] = client_config.get("enable", True)
    desired["fields"] = merge_fields(existing.get("fields", []), client_config["fields"], "Download-client")
    if desired != existing:
        request_json(base_url, api_key, f"{endpoint}/{existing['id']}", "PUT", desired)


def _first_profile_id(base_url: str, api_key: str, endpoint: str) -> int:
    profiles = request_json(base_url, api_key, endpoint)
    if not isinstance(profiles, list):
        raise ReconciliationError("Lidarr returned an unsupported profile list")

    profile_ids = [
        profile.get("id")
        for profile in profiles
        if isinstance(profile, dict)
        and isinstance(profile.get("id"), int)
        and not isinstance(profile.get("id"), bool)
        and profile["id"] > 0
    ]
    if not profile_ids:
        raise ReconciliationError(f"Lidarr has no usable {endpoint} entries for a root folder")
    return min(profile_ids)


def ensure_root_folder(base_url: str, api_key: str, path: str, application: str = "") -> None:
    roots = request_json(base_url, api_key, "rootfolder")
    existing = unique_match(roots, lambda item: item.get("path") == path, f"root folder '{path}'")
    if existing is None:
        payload = {"path": path}
        if application == "lidarr":
            payload.update(
                {
                    "name": pathlib.PurePosixPath(path).name,
                    "defaultMetadataProfileId": _first_profile_id(base_url, api_key, "metadataprofile"),
                    "defaultQualityProfileId": _first_profile_id(base_url, api_key, "qualityprofile"),
                }
            )
        request_json(base_url, api_key, "rootfolder", "POST", payload)


def _normalize_directory_path(path: str, name: str) -> str:
    if not isinstance(path, str) or not path.startswith("/"):
        raise ReconciliationError(f"Arr {name} must be an absolute path")

    normalized = path.replace("\\", "/")
    while "//" in normalized:
        normalized = normalized.replace("//", "/")
    normalized = normalized.rstrip("/")
    return f"{normalized}/" if normalized else "/"


def ensure_remote_path_mapping(
    base_url: str,
    api_key: str,
    mapping: dict[str, str],
) -> None:
    mapping = dict(mapping)
    mapping["remotePath"] = _normalize_directory_path(mapping["remotePath"], "remote path")
    mapping["localPath"] = _normalize_directory_path(mapping["localPath"], "local path")

    endpoint = "remotePathMapping"
    mappings = request_json(base_url, api_key, endpoint)
    existing = unique_match(
        mappings,
        lambda item: item.get("host", "").casefold() == mapping["host"].casefold()
        and _normalize_directory_path(item.get("remotePath", ""), "remote path") == mapping["remotePath"],
        "remote-path mapping",
    )
    if existing is None:
        try:
            request_json(base_url, api_key, endpoint, "POST", mapping)
            return
        except ReconciliationError as create_error:
            # Another settings sync can create the same mapping between our GET
            # and POST. Re-read before failing so startup races remain safe.
            try:
                mappings = request_json(base_url, api_key, endpoint)
                existing = unique_match(
                    mappings,
                    lambda item: item.get("host", "").casefold() == mapping["host"].casefold()
                    and _normalize_directory_path(item.get("remotePath", ""), "remote path") == mapping["remotePath"],
                    "remote-path mapping",
                )
            except ReconciliationError:
                raise create_error
            if existing is None:
                raise create_error

    desired = dict(existing)
    desired.update(mapping)
    if desired != existing:
        request_json(base_url, api_key, f"{endpoint}/{existing['id']}", "PUT", desired)
