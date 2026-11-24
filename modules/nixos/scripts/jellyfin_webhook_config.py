"""Reconcile Jellyfin's official Discord ItemAdded webhook at runtime."""

from __future__ import annotations

import argparse
import base64
import copy
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from media_api_reconcile import ReconciliationError, open_local_url


PLUGIN_ID = "71552A5A-5C5C-4350-A2AE-EBE451A30173"
DESTINATION_NAME = "Jellyfin New Media (Nix)"
CLIENT = 'MediaBrowser Client="Drlight NixOS Discord Notifications", Device="Drlight", DeviceId="drlight-jellyfin-discord-notifications", Version="1"'
DISCORD_TEMPLATE = r'''{
    "content": "{{MentionType}}",
    "avatar_url": "{{AvatarUrl}}",
    "username": "{{BotUsername}}",
    "embeds": [
        {
            "author": {
                {{#if_equals ItemType 'Season'}}
                    "name": "Season Added • {{{SeriesName}}} {{{Name}}}",
                {{/if_equals}}
                {{#if_equals ItemType 'Episode'}}
                    "name": "Episode Added • {{{SeriesName}}} S{{SeasonNumber00}}E{{EpisodeNumber00}} ~ {{{Name}}}",
                {{/if_equals}}
                {{#if_equals ItemType 'Movie'}}
                    "name": "Movie Added • {{{Name}}}",
                {{/if_equals}}
                {{#if_equals ItemType 'Series'}}
                    "name": "Series Added • {{{Name}}}",
                {{/if_equals}}
                {{#if_equals ItemType 'MusicAlbum'}}
                    "name": "Album Added • {{{Name}}}",
                {{/if_equals}}
                {{#if_equals ItemType 'Audio'}}
                    "name": "Song Added • {{{Name}}}",
                {{/if_equals}}
                {{#if_equals ItemType 'Video'}}
                    "name": "Video Added • {{{Name}}}",
                {{/if_equals}}
                "url": "{{ServerUrl}}/web/index.html#!/details?id={{ItemId}}&serverId={{ServerId}}"
            },
            "thumbnail": {
                "url": "{{ServerUrl}}/Items/{{ItemId}}/Images/Primary"
            },
            "description": "{{~#if_exist Overview~}}> {{{Overview}}}\n\n{{~/if_exist~}}[**Watch Now**]({{ServerUrl}}/web/index.html#!/details?id={{ItemId}}&serverId={{ServerId}})",
            "color": {{EmbedColor}},
            "footer": {
                "text": "{{{ServerName}}}",
                "icon_url": "{{AvatarUrl}}"
            },
            "timestamp": "{{Timestamp}}"
        }
    ]
}'''


class JellyfinRetryableError(ReconciliationError):
    """Jellyfin is temporarily unavailable while its service starts."""


def _read_secret(path: str, description: str) -> str:
    try:
        value = pathlib.Path(path).read_text(encoding="utf-8").strip()
    except OSError as error:
        raise ReconciliationError(f"The configured {description} file is unavailable") from error
    if not value:
        raise ReconciliationError(f"The configured {description} file is empty")
    return value


def _validate_local_base_url(base_url: str) -> str:
    parsed = urllib.parse.urlsplit(base_url)
    if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
        raise ReconciliationError("Jellyfin webhook reconciliation is restricted to loopback HTTP")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ReconciliationError("Jellyfin webhook reconciliation requires a plain local base URL")
    return base_url.rstrip("/")


def _validate_discord_webhook(webhook_url: str) -> str:
    parsed = urllib.parse.urlsplit(webhook_url)
    if (
        parsed.scheme != "https"
        or parsed.hostname not in {"discord.com", "discordapp.com"}
        or not parsed.path.startswith("/api/webhooks/")
        or parsed.username
        or parsed.password
        or parsed.port not in {None, 443}
        or parsed.fragment
    ):
        raise ReconciliationError("The configured Discord webhook URL is invalid")
    return webhook_url


def _request_json(
    base_url: str,
    endpoint: str,
    authorization: str,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
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
        if status in {502, 503, 504}:
            raise JellyfinRetryableError("Jellyfin API is temporarily unavailable") from error
        raise ReconciliationError(f"Jellyfin API request failed with HTTP {status}") from error
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise JellyfinRetryableError("Jellyfin API request could not reach the local service") from error

    if not body:
        return {}
    try:
        result = json.loads(body.decode("utf-8"))
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
    payload: dict[str, Any] | None = None,
    timeout_seconds: int = 60,
) -> dict[str, Any]:
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


def _authenticate_admin(base_url: str, username: str, password: str) -> str:
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

    authorization = f'{CLIENT}, Token="{token}"'
    user = _request_when_ready(base_url, "Users/Me", authorization)
    policy = user.get("Policy") or user.get("policy") or {}
    if policy.get("IsAdministrator", policy.get("isAdministrator", False)) is not True:
        raise ReconciliationError("Configured Jellyfin account is not an administrator")
    return authorization


def _managed_discord_option(webhook_url: str) -> dict[str, Any]:
    return {
        "WebhookName": DESTINATION_NAME,
        "WebhookUri": webhook_url,
        "EnableWebhook": True,
        "NotificationTypes": ["ItemAdded"],
        "EnableMovies": True,
        "EnableEpisodes": True,
        "EnableSeasons": True,
        "EnableSeries": True,
        "EnableAlbums": True,
        "EnableSongs": True,
        "EnableVideos": True,
        "SendAllProperties": False,
        "TrimWhitespace": True,
        "SkipEmptyMessageBody": True,
        "UserFilter": [],
        "Template": base64.b64encode(DISCORD_TEMPLATE.encode("utf-8")).decode("ascii"),
        "EmbedColor": "#33B39F",
        "Username": "Jellyfin",
        "AvatarUrl": "",
        "MentionType": 0,
    }


def build_webhook_configuration(
    existing: dict[str, Any],
    webhook_url: str,
    server_url: str,
) -> dict[str, Any]:
    """Upsert the Nix-owned Discord destination without replacing other plugin settings."""
    if not isinstance(existing, dict):
        raise ReconciliationError("Jellyfin Webhook plugin returned an unsupported configuration")
    config = copy.deepcopy(existing)
    discord_options = config.get("DiscordOptions", [])
    if not isinstance(discord_options, list) or any(not isinstance(item, dict) for item in discord_options):
        raise ReconciliationError("Jellyfin Webhook plugin returned unsupported Discord destinations")

    indexes = [
        index
        for index, option in enumerate(discord_options)
        if option.get("WebhookName") == DESTINATION_NAME
    ]
    if len(indexes) > 1:
        raise ReconciliationError("Multiple Jellyfin Discord destinations have the managed name")

    managed = _managed_discord_option(webhook_url)
    if indexes:
        discord_options[indexes[0]] = managed
    else:
        discord_options.append(managed)

    config["ServerUrl"] = server_url
    config["DiscordOptions"] = discord_options
    return config


def reconcile(config: dict[str, Any]) -> None:
    """Authenticate locally and update the plugin configuration if it differs."""
    if not isinstance(config, dict):
        raise ReconciliationError("Jellyfin Webhook reconciler config must be an object")
    base_url = _validate_local_base_url(config["baseUrl"])
    server_url = str(config["serverUrl"]).rstrip("/")
    if urllib.parse.urlsplit(server_url).scheme not in {"http", "https"}:
        raise ReconciliationError("The configured Jellyfin server URL is invalid")

    username = _read_secret(config["usernameFile"], "Jellyfin username")
    password = _read_secret(config["passwordFile"], "Jellyfin password")
    webhook_url = _validate_discord_webhook(_read_secret(config["webhookUrlFile"], "Discord webhook URL"))
    _request_when_ready(base_url, "System/Info/Public", CLIENT)
    authorization = _authenticate_admin(base_url, username, password)
    endpoint = f"Plugins/{PLUGIN_ID}/Configuration"
    existing = _request_when_ready(base_url, endpoint, authorization)
    desired = build_webhook_configuration(existing, webhook_url, server_url)
    if desired != existing:
        _request_when_ready(base_url, endpoint, authorization, method="POST", payload=desired)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=pathlib.Path)
    args = parser.parse_args(argv)
    try:
        config = json.loads(args.config.read_text(encoding="utf-8"))
        reconcile(config)
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ReconciliationError) as error:
        print(f"Jellyfin Webhook configuration failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
