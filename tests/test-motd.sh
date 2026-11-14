#!/usr/bin/env bash
set -euo pipefail

: "${MOTD_SCRIPT:?MOTD_SCRIPT must point to modules/common/motd.sh}"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/home"

cat > "$tmp_dir/bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"

output=""
url=""
previous=""
for argument in "$@"; do
  if [[ "$previous" == "-o" ]]; then
    output=$argument
  fi
  if [[ "$argument" == https://* ]]; then
    url=$argument
  fi
  previous=$argument
done
case "$url" in
  https://science.nasa.gov/feed/apod-basic/)
    cat > "$output" <<'RSS'
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:apod="https://science.nasa.gov/apod/">
  <channel>
    <item>
      <title>Test &amp; APOD title</title>
      <apod:hdurl>https://images.example.test/apod.jpg?original=1&amp;quality=full</apod:hdurl>
    </item>
  </channel>
</rss>
RSS
    ;;
  https://images.example.test/*)
    printf 'mock image data\n' > "$output"
    ;;
  *)
    if [[ -n "$output" ]]; then
      : > "$output"
    fi
    ;;
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

output_file="$tmp_dir/motd-output"
bash "$MOTD_SCRIPT" > "$output_file"

feed_request=$(grep 'https://science.nasa.gov/feed/apod-basic/' "$CURL_LOG")
[[ "$feed_request" == *'--max-time 5'* && "$feed_request" == *'--fail'* ]] || {
  echo 'APOD feed request must fail on HTTP errors and have a 5-second maximum time' >&2
  exit 1
}

image_request=$(grep 'https://images.example.test/apod.jpg' "$CURL_LOG")
[[ "$image_request" == *'--max-time 5'* && "$image_request" == *'--fail'* ]] || {
  echo 'APOD image request must fail on HTTP errors and have a 5-second maximum time' >&2
  exit 1
}
[[ "$image_request" == *'?w=200&h=200&fit=crop'* ]] || {
  echo 'APOD thumbnail request must ask NASA for a 200x200 crop' >&2
  exit 1
}

[[ "$(<"$HOME/.cache/motd/title")" == 'Test & APOD title' ]] || {
  echo 'MOTD must cache the decoded APOD title' >&2
  exit 1
}
full_size_url='https://images.example.test/apod.jpg?original=1&quality=full'
[[ "$(<"$HOME/.cache/motd/full-size-url")" == "$full_size_url" ]] || {
  echo 'MOTD must cache the original full-size APOD URL' >&2
  exit 1
}
grep -F 'Test & APOD title' "$output_file" >/dev/null || {
  echo 'MOTD must display the APOD title' >&2
  exit 1
}
grep -F "$full_size_url" "$output_file" >/dev/null || {
  echo 'MOTD title hyperlink must target the full-size image' >&2
  exit 1
}
[[ -f "$HOME/.cache/motd/daily.jpg" && -f "$HOME/.cache/motd/timestamp" ]] || {
  echo 'MOTD must cache the APOD image and fetch date' >&2
  exit 1
}

echo 'MOTD fetches and displays a linked, cached APOD thumbnail: OK'
