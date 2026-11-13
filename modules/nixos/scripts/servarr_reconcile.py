"""Reconcile the migration-critical resources for one Servarr application."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import urllib.parse
from typing import Any

from media_api_reconcile import (
    ReconciliationError,
    ensure_remote_path_mapping,
    ensure_root_folder,
    expand_runtime_secrets,
    read_arr_api_key,
    request_json,
    upsert_download_client,
    wait_for_arr_api,
)


def transmission_fields(config: dict[str, Any]) -> tuple[dict[str, Any], str]:
    rpc_url = expand_runtime_secrets(config["rpcUrl"])
    parsed = urllib.parse.urlsplit(rpc_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ReconciliationError("Transmission RPC URL must be an absolute HTTP(S) URL")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ReconciliationError("Transmission RPC URL must not embed credentials or query data")
    if parsed.scheme != "https" and parsed.hostname not in {"127.0.0.1", "::1", "localhost"}:
        raise ReconciliationError("Remote Transmission RPC must use HTTPS")

    try:
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
    except ValueError as error:
        raise ReconciliationError("Transmission RPC URL has an invalid port") from error

    url_base = parsed.path.rstrip("/")
    if url_base.endswith("/rpc"):
        url_base = url_base[:-4].rstrip("/")

    fields = {
        "host": parsed.hostname,
        "port": port,
        "useSsl": parsed.scheme == "https",
        "username": expand_runtime_secrets(config["username"]),
        "password": expand_runtime_secrets(config["password"]),
    }
    if url_base:
        fields["urlBase"] = url_base

    remote_path = expand_runtime_secrets(config["remotePath"])
    if not isinstance(remote_path, str) or not remote_path.startswith("/"):
        raise ReconciliationError("Transmission completed-download path must be absolute")
    return fields, remote_path


def reconcile_authentication(base_url: str, api_key: str, auth: dict[str, Any]) -> None:
    username = expand_runtime_secrets(auth["username"])
    password = expand_runtime_secrets(auth["password"])
    if not isinstance(username, str) or not username or not isinstance(password, str) or not password:
        raise ReconciliationError("Arr administrator username or password is empty")

    current = request_json(base_url, api_key, "config/host")
    if not isinstance(current, dict):
        raise ReconciliationError("Arr host configuration has an unsupported format")

    host_id = current.get("id")
    if not isinstance(host_id, (str, int)) or not str(host_id).isdigit():
        raise ReconciliationError("Arr host configuration is missing its resource ID")
    endpoint = f"config/host/{host_id}"

    desired = dict(current)
    desired.update(
        {
            "authenticationMethod": "Forms",
            "authenticationRequired": "Enabled",
            "username": username,
            "password": password,
            "passwordConfirmation": password,
        }
    )
    if desired != current:
        request_json(base_url, api_key, endpoint, "PUT", desired)


def reconcile(config: dict[str, Any]) -> None:
    base_url = config["baseUrl"].rstrip("/")
    api_key = read_arr_api_key(config["configXml"])
    wait_for_arr_api(base_url, api_key)
    transmission = config.get("transmission")
    if transmission:
        transmission = expand_runtime_secrets(transmission)
        fields, remote_path = transmission_fields(transmission)

        # The RPC endpoint itself is read at runtime from the secret file. Keep
        # the rest of the Transmission config in a JSON-friendly structure.
        downloader = {
            "name": transmission.get("name", "Transmission"),
            "implementation": "Transmission",
            "enable": True,
            "fields": fields,
        }
        upsert_download_client(base_url, api_key, downloader)

    for path in config.get("rootFolders", []):
        ensure_root_folder(base_url, api_key, path, config.get("application", ""))

    if transmission:
        ensure_remote_path_mapping(
            base_url,
            api_key,
            {
                "host": urllib.parse.urlsplit(expand_runtime_secrets(transmission["rpcUrl"])).hostname,
                "remotePath": remote_path,
                "localPath": transmission["localPath"],
            },
        )

    auth = config.get("auth")
    if auth is not None:
        reconcile_authentication(base_url, api_key, auth)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        config = json.loads(args.config.read_text(encoding="utf-8"))
        reconcile(config)
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ReconciliationError) as error:
        print(f"Servarr reconciliation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
