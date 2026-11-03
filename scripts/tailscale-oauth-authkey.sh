#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: tailscale-oauth-authkey.sh <machine> <tags-json>" >&2
  exit 64
fi

machine=$1
tags_json=$2
client_id=${TAILSCALE_OAUTH_CLIENT_ID:?TAILSCALE_OAUTH_CLIENT_ID must be resolved from SecretSpec}
client_secret=${TAILSCALE_OAUTH_CLIENT_SECRET:?TAILSCALE_OAUTH_CLIENT_SECRET must be resolved from SecretSpec}
curl_bin=${CURL_BIN:-curl}
jq_bin=${JQ_BIN:-jq}

[[ "$machine" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] || {
  echo "Invalid machine name" >&2
  exit 64
}
"$jq_bin" -e 'type == "array" and length > 0 and all(.[]; type == "string" and test("^tag:[a-z0-9-]+$")) and (length == (unique | length))' <<< "$tags_json" >/dev/null || {
  echo "Tags must be a non-empty JSON array of unique Tailscale tags" >&2
  exit 64
}

tags=$("$jq_bin" -r 'join(" ")' <<< "$tags_json")
token_response=$(
  "$curl_bin" --fail --silent --show-error \
    --config <(printf 'user = "%s:%s"\n' "$client_id" "$client_secret") \
    --request POST \
    --url "https://api.tailscale.com/api/v2/oauth/token" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "scope=auth_keys" \
    --data-urlencode "tags=$tags"
)
access_token=$("$jq_bin" -er '.access_token | strings | select(length > 0)' <<< "$token_response")

key_request=$("$jq_bin" -cn \
  --arg machine "$machine" \
  --argjson tags "$tags_json" \
  '{
    capabilities: {
      devices: {
        create: {
          reusable: false,
          ephemeral: false,
          preauthorized: true,
          tags: $tags
        }
      }
    },
    expirySeconds: 86400,
    description: ("Devenv deployment for " + $machine)
  }')
key_response=$(
  "$curl_bin" --fail --silent --show-error \
    --config <(printf 'header = "Authorization: Bearer %s"\n' "$access_token") \
    --request POST \
    --url "https://api.tailscale.com/api/v2/tailnet/-/keys" \
    --header "Content-Type: application/json" \
    --data-binary "$key_request"
)
auth_key=$("$jq_bin" -er '.key | strings | select(length > 0)' <<< "$key_response")
printf '%s' "$auth_key"
