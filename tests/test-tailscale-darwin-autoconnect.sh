#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper=${TAILSCALE_DARWIN_AUTH_SCRIPT:-"$repo_root/scripts/tailscale-darwin-autoconnect.sh"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '%s\n' Starting NeedsLogin > "$tmp/states"
printf '1\n' > "$tmp/state-index"
: > "$tmp/calls"

printf '#!%s\n' "$BASH" > "$tmp/bin/tailscale"
cat >> "$tmp/bin/tailscale" <<'MOCK'
set -euo pipefail
case "${1:-}" in
  status)
    index=$(cat "$TAILSCALE_STATE_INDEX")
    state=$(sed -n "${index}p" "$TAILSCALE_STATE_SEQUENCE")
    index=$((index + 1))
    printf '%s\n' "$index" > "$TAILSCALE_STATE_INDEX"
    if [[ "$state" == __EMPTY__ ]]; then
      printf 'status:empty\n' >> "$TAILSCALE_CALL_LOG"
      printf '{"BackendState":""}\n'
      exit 0
    fi
    if [[ -z "$state" ]]; then
      state=$(tail -n 1 "$TAILSCALE_STATE_SEQUENCE")
    fi
    printf 'status:%s\n' "$state" >> "$TAILSCALE_CALL_LOG"
    printf '{"BackendState":"%s"}\n' "$state"
    ;;
  up)
    printf 'up:%s\n' "$*" >> "$TAILSCALE_CALL_LOG"
    ;;
  *)
    echo "unexpected tailscale invocation: $*" >&2
    exit 90
    ;;
esac
MOCK
printf '#!%s\n' "$BASH" > "$tmp/bin/jq"
cat >> "$tmp/bin/jq" <<'MOCK'
set -euo pipefail
json=$(cat)
case "$json" in
  *'"BackendState":"Running"'*) printf 'Running\n' ;;
  *'"BackendState":"NeedsLogin"'*) printf 'NeedsLogin\n' ;;
  *'"BackendState":"Starting"'*) printf 'Starting\n' ;;
  *'"BackendState":"NoState"'*) printf 'NoState\n' ;;
  *'"BackendState":"Unsupported"'*) printf 'Unsupported\n' ;;
  *) exit 1 ;;
esac
MOCK
printf '#!%s\n' "$BASH" > "$tmp/bin/sleep"
cat >> "$tmp/bin/sleep" <<'MOCK'
exit 0
MOCK
chmod +x "$tmp/bin/tailscale" "$tmp/bin/jq" "$tmp/bin/sleep"

run_auth() {
  local states=$1
  local expected_status=$2
  local key_file=$3
  printf '%s\n' "$states" > "$TAILSCALE_STATE_SEQUENCE"
  printf '1\n' > "$TAILSCALE_STATE_INDEX"
  : > "$TAILSCALE_CALL_LOG"
  TAILSCALE_STATE_SEQUENCE="$TAILSCALE_STATE_SEQUENCE" \
  TAILSCALE_STATE_INDEX="$TAILSCALE_STATE_INDEX" \
  TAILSCALE_CALL_LOG="$TAILSCALE_CALL_LOG" \
    "$BASH" "$helper" "$key_file" "$tmp/bin/tailscale" "$tmp/bin/jq" "$tmp/bin/sleep" 3 0 \
      "--auth-key=file:$key_file"
  [[ "$(cat "$TAILSCALE_CALL_LOG")" == "$expected_status" ]]
}

TAILSCALE_STATE_SEQUENCE="$tmp/states"
TAILSCALE_STATE_INDEX="$tmp/state-index"
TAILSCALE_CALL_LOG="$tmp/calls"

# A transient Starting state is retried; authentication only runs once the
# backend reports NeedsLogin, and the staged key is removed after success.
starting_key="$tmp/starting-auth-key"
printf '%s' 'synthetic-key' > "$starting_key"
run_auth $'Starting\nNeedsLogin' $'status:Starting\nstatus:NeedsLogin\nup:up --auth-key=file:'"$starting_key" "$starting_key"
[[ ! -e "$starting_key" ]]

# NoState and an empty backend response are retried until the daemon reports NeedsLogin.
no_state_key="$tmp/no-state-auth-key"
printf '%s' 'synthetic-key' > "$no_state_key"
run_auth $'NoState\nNeedsLogin' $'status:NoState\nstatus:NeedsLogin\nup:up --auth-key=file:'"$no_state_key" "$no_state_key"
[[ ! -e "$no_state_key" ]]
empty_state_key="$tmp/empty-state-auth-key"
printf '%s' 'synthetic-key' > "$empty_state_key"
run_auth $'__EMPTY__\nNeedsLogin' $'status:empty\nstatus:NeedsLogin\nup:up --auth-key=file:'"$empty_state_key" "$empty_state_key"
[[ ! -e "$empty_state_key" ]]

# Already connected nodes need no login and the one-time staged key is cleaned.
running_key="$tmp/running-auth-key"
printf '%s' 'synthetic-key' > "$running_key"
run_auth 'Running' 'status:Running' "$running_key"
[[ ! -e "$running_key" ]]

# Unsupported states fail closed without attempting auth or consuming the key.
unsupported_key="$tmp/unsupported-auth-key"
printf '%s' 'synthetic-key' > "$unsupported_key"
printf '%s\n' Unsupported > "$TAILSCALE_STATE_SEQUENCE"
printf '1\n' > "$TAILSCALE_STATE_INDEX"
: > "$TAILSCALE_CALL_LOG"
if TAILSCALE_STATE_SEQUENCE="$TAILSCALE_STATE_SEQUENCE" \
  TAILSCALE_STATE_INDEX="$TAILSCALE_STATE_INDEX" \
  TAILSCALE_CALL_LOG="$TAILSCALE_CALL_LOG" \
  "$BASH" "$helper" "$unsupported_key" "$tmp/bin/tailscale" "$tmp/bin/jq" "$tmp/bin/sleep" 3 0 \
    "--auth-key=file:$unsupported_key" >"$tmp/unsupported-output" 2>&1; then
  echo 'unsupported Tailscale state unexpectedly succeeded' >&2
  exit 1
fi
[[ "$(cat "$TAILSCALE_CALL_LOG")" == 'status:Unsupported' ]]
[[ -e "$unsupported_key" ]]
if grep -q '^up:' "$TAILSCALE_CALL_LOG"; then
  echo 'unsupported Tailscale state attempted authentication' >&2
  exit 1
fi

# Retry exhaustion is fail-closed and preserves the key for controller cleanup.
retry_key="$tmp/retry-auth-key"
printf '%s' 'synthetic-key' > "$retry_key"
printf '%s\n' Starting > "$TAILSCALE_STATE_SEQUENCE"
printf '1\n' > "$TAILSCALE_STATE_INDEX"
: > "$TAILSCALE_CALL_LOG"
set +e
TAILSCALE_STATE_SEQUENCE="$TAILSCALE_STATE_SEQUENCE" \
TAILSCALE_STATE_INDEX="$TAILSCALE_STATE_INDEX" \
TAILSCALE_CALL_LOG="$TAILSCALE_CALL_LOG" \
  "$BASH" "$helper" "$retry_key" "$tmp/bin/tailscale" "$tmp/bin/jq" "$tmp/bin/sleep" 3 0 \
    "--auth-key=file:$retry_key" >"$tmp/retry-output" 2>&1
retry_status=$?
set -e
[[ "$retry_status" -ne 0 ]]
[[ $(grep -c '^status:Starting$' "$TAILSCALE_CALL_LOG") -eq 3 ]]
[[ -e "$retry_key" ]]
if grep -q '^up:' "$TAILSCALE_CALL_LOG"; then
  echo 'retry exhaustion attempted authentication' >&2
  exit 1
fi

echo 'Darwin Tailscale auth-state tests passed'
