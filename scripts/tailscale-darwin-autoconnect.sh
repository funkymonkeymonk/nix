#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "Usage: tailscale-darwin-autoconnect.sh <auth-key-file> <tailscale-bin> <jq-bin> <sleep-bin> <attempts> <sleep-seconds> <up-flags>" >&2
  exit 64
fi

auth_key_file=$1
tailscale_bin=$2
jq_bin=$3
sleep_bin=$4
max_attempts=$5
sleep_seconds=$6
up_flags=$7

[[ "$max_attempts" =~ ^[1-9][0-9]*$ ]] || {
  echo "Invalid Tailscale status retry count" >&2
  exit 64
}
[[ "$sleep_seconds" =~ ^[0-9]+$ ]] || {
  echo "Invalid Tailscale status retry delay" >&2
  exit 64
}

if [[ ! -f "$auth_key_file" || -L "$auth_key_file" ]]; then
  exit 0
fi

read -r -a tailscale_up_args <<< "$up_flags"

for ((attempt = 1; attempt <= max_attempts; attempt += 1)); do
  status_json=$("$tailscale_bin" status --json 2>/dev/null || true)
  backend_state=$(printf '%s' "$status_json" | "$jq_bin" -r '.BackendState // empty' 2>/dev/null || true)

  case "$backend_state" in
    Running)
      rm -f -- "$auth_key_file"
      exit 0
      ;;
    NeedsLogin)
      "$tailscale_bin" up "${tailscale_up_args[@]}"
      rm -f -- "$auth_key_file"
      exit 0
      ;;
    Starting|NoState|"")
      "$sleep_bin" "$sleep_seconds"
      ;;
    *)
      echo "Tailscale backend state is unsupported ('$backend_state'); refusing OAuth enrollment" >&2
      exit 1
      ;;
  esac
done

echo "Tailscale daemon did not reach an enrollable backend state" >&2
exit 1
