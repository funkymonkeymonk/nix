#!/usr/bin/env bash
set -euo pipefail

: "${MOTD_SCRIPT:?MOTD_SCRIPT must point to modules/common/motd.sh}"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/home"

cat > "$tmp_dir/bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
case "$*" in
  *https://picsum.photos/200/200*) exit 28 ;;
  *) exit 0 ;;
esac
MOCK_CURL
chmod +x "$tmp_dir/bin/curl"
cat > "$tmp_dir/bin/hostname" <<'MOCK_HOSTNAME'
#!/usr/bin/env bash
printf 'motd-test-host\n'
MOCK_HOSTNAME
chmod +x "$tmp_dir/bin/hostname"

export CURL_LOG="$tmp_dir/curl.log"
export HOME="$tmp_dir/home"
export PATH="$tmp_dir/bin:$PATH"
export MOTD_SHOW_HOSTNAME=0
export MOTD_SHOW_GIT_COMMIT=0
export TERM=dumb

bash "$MOTD_SCRIPT" >/dev/null

image_request=$(grep 'https://picsum.photos/200/200' "$CURL_LOG")
[[ "$image_request" == *'--max-time 5'* ]] || {
  echo 'MOTD image request must have a 5-second maximum time' >&2
  exit 1
}
[[ "$image_request" == *'--fail'* ]] || {
  echo 'MOTD image request must reject HTTP error responses' >&2
  exit 1
}
[[ ! -e "$HOME/.cache/motd/daily.jpg" ]] || {
  echo 'MOTD must not cache a failed image response' >&2
  exit 1
}

echo 'MOTD image fetch is time-bounded and rejects failed requests: OK'
