#!/usr/bin/env bash
set -euo pipefail

: "${AUTHKEY_SCRIPT:?set AUTHKEY_SCRIPT}"
: "${BASH_BIN:?set BASH_BIN}"
: "${JQ_BIN:?set JQ_BIN}"

command -v mktemp >/dev/null

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export CURL_LOG="$tmp/curl.log"
export KEY_REQUEST="$tmp/key-request.json"
export CURL_BIN="$tmp/bin/curl"

printf '#!%s\n' "$BASH_BIN" > "$CURL_BIN"
cat >> "$CURL_BIN" <<'MOCK'
set -euo pipefail
printf '%s\n' "$*" >> "$CURL_LOG"
url=""
previous=''
for argument in "$@"; do
  if [[ "$previous" == --url ]]; then url=$argument; fi
  previous=$argument
done
if [[ "$url" == */oauth/token ]]; then
  printf '{"access_token":"unit-test-access-token","expires_in":3600}\n'
elif [[ "$url" == */tailnet/-/keys ]]; then
  previous=''
  for argument in "$@"; do
    if [[ "$previous" == --data-binary || "$previous" == --data ]]; then
      printf '%s' "$argument" > "$KEY_REQUEST"
    fi
    previous=$argument
  done
  printf '{"key":"tskey-auth-one-use-test"}\n'
else
  echo "Unexpected Tailscale API endpoint" >&2
  exit 98
fi
MOCK
chmod +x "$CURL_BIN"

export TAILSCALE_OAUTH_CLIENT_ID='test-client-id'
export TAILSCALE_OAUTH_CLIENT_SECRET='test-client-secret'
stdout=$("$BASH_BIN" "$AUTHKEY_SCRIPT" drlight '["tag:home-lab","tag:media-center"]' 2>"$tmp/stderr")

[[ "$stdout" == 'tskey-auth-one-use-test' ]] || {
  echo 'auth-key helper did not return only the generated key' >&2
  exit 1
}
[[ ! -s "$tmp/stderr" ]] || {
  echo 'auth-key helper unexpectedly logged output to stderr' >&2
  cat "$tmp/stderr" >&2
  exit 1
}
"$JQ_BIN" -e '
  .expirySeconds == 86400
  and .description == "Devenv deployment for drlight"
  and .capabilities.devices.create.reusable == false
  and .capabilities.devices.create.ephemeral == false
  and .capabilities.devices.create.preauthorized == true
  and .capabilities.devices.create.tags == ["tag:home-lab", "tag:media-center"]
' "$KEY_REQUEST" >/dev/null

grep -F 'scope=auth_keys' "$CURL_LOG" >/dev/null
grep -F 'tags=tag:home-lab tag:media-center' "$CURL_LOG" >/dev/null
if grep -E 'test-client-secret|unit-test-access-token|tskey-auth-one-use-test' "$CURL_LOG"; then
  echo 'OAuth credentials or returned auth key were exposed in curl arguments' >&2
  exit 1
fi

printf 'Tailscale OAuth one-time auth-key tests passed\n'
