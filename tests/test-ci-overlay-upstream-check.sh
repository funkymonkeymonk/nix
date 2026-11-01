#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-overlay-upstream-urls.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/nix" <<'MOCK_NIX'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"package":"jj-hooks","version":"0.6.0","urls":["https://example.test/jj-hooks-linux-x64.tar.gz"]},
  {"package":"jj-hooks","version":"0.6.0","urls":["https://example.test/jj-hooks-linux-arm64.tar.gz"]},
  {"package":"jj-hooks","version":"0.6.0","urls":["https://example.test/jj-hooks-darwin-arm64.tar.gz"]},
  {"package":"mlx-audio","version":"1.2.3","urls":["mirror://pypi/m/mlx_audio/mlx_audio-1.2.3.tar.gz"]}
]
JSON
MOCK_NIX

cat > "$TMP_DIR/bin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail
url="${@: -1}"
if [[ "$url" == https://pypi.org/pypi/* ]]; then
  printf '%s\n' '{"urls":[{"filename":"mlx_audio-1.2.3.tar.gz","url":"https://files.pythonhosted.org/packages/mlx_audio-1.2.3.tar.gz"}]}'
  exit 0
fi
printf '%s\n' "$url" >> "$CURL_LOG"
if [[ "$url" == "${CURL_FAIL_URL:-}" ]]; then
  echo "simulated HTTP 404 for $url" >&2
  exit 22
fi
MOCK_CURL
chmod +x "$TMP_DIR/bin/nix" "$TMP_DIR/bin/curl"

run_check() {
  local fail_url="${1:-}"
  CURL_LOG="$TMP_DIR/curl.log" \
    CURL_FAIL_URL="$fail_url" \
    NIX_BIN="$TMP_DIR/bin/nix" \
    CURL_BIN="$TMP_DIR/bin/curl" \
    OVERLAY_SOURCE_CONFIGS="nixosConfigurations.test.pkgs" \
    bash "$SCRIPT"
}

if ! output="$(run_check 2>&1)"; then
  echo "$output"
  echo "FAIL: source availability check should pass when all URLs are reachable" >&2
  exit 1
fi

if [[ "$(wc -l < "$TMP_DIR/curl.log")" -ne 4 ]]; then
  echo "FAIL: expected every platform asset and the PyPI artifact URL to be probed" >&2
  cat "$TMP_DIR/curl.log" >&2
  exit 1
fi
for platform in linux-x64 linux-arm64 darwin-arm64; do
  if ! grep -Fq "https://example.test/jj-hooks-${platform}.tar.gz" "$TMP_DIR/curl.log"; then
    echo "FAIL: jj-hooks $platform release URL was not checked" >&2
    exit 1
  fi
done
if ! grep -Fq 'https://files.pythonhosted.org/packages/mlx_audio-1.2.3.tar.gz' "$TMP_DIR/curl.log"; then
  echo "FAIL: PyPI mirror URL was not resolved to its artifact URL" >&2
  exit 1
fi

if run_check 'https://example.test/jj-hooks-linux-x64.tar.gz' >"$TMP_DIR/failure.log" 2>&1; then
  echo "FAIL: source availability check should fail when an upstream URL returns 404" >&2
  exit 1
fi
if ! grep -Fq 'jj-hooks' "$TMP_DIR/failure.log"; then
  echo "FAIL: failure output should identify the affected package" >&2
  cat "$TMP_DIR/failure.log" >&2
  exit 1
fi

echo "Overlay upstream source checks passed"
