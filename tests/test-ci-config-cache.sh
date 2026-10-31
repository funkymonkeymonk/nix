#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/.github/scripts/check-config-changes.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/cache"
cat > "$TMP_DIR/bin/nix" <<'MOCK_NIX'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == eval ]] || exit 64
[[ "$*" == *--raw* ]] || exit 66
installable="${@: -1}"
case "$installable" in
  *darwinConfigurations.*) config="${installable#*darwinConfigurations.}" ;;
  *nixosConfigurations.*)
    [[ "$*" == *--impure* ]] || exit 65
    config="${installable#*nixosConfigurations.}"
    ;;
  *) exit 1 ;;
esac
config="${config%%.*}"
printf '/nix/store/%s.drv\n' "$config"
MOCK_NIX
cat > "$TMP_DIR/bin/nix-store" <<'MOCK_STORE'
#!/usr/bin/env bash
set -euo pipefail
drv="${@: -1}"
name="$(basename "$drv" .drv)"
if [[ "${FAIL_HASH_FOR:-}" == "$name" ]]; then
  exit 1
fi
if [[ "${CHANGED_HASH_FOR:-}" == "$name" ]]; then
  printf 'changed-hash\n'
  exit 0
fi
case "$name" in
  existing-darwin|existing-linux) printf 'old-hash\n' ;;
  *) printf 'hash-%s\n' "$name" ;;
esac
MOCK_STORE
chmod +x "$TMP_DIR/bin/nix" "$TMP_DIR/bin/nix-store"

cat > "$TMP_DIR/cache/darwin-configs" <<'DARWIN_CACHE'
["existing-darwin"]
DARWIN_CACHE
printf 'old-hash\n' > "$TMP_DIR/cache/darwin-existing-darwin.hash"
cat > "$TMP_DIR/cache/nixos-configs" <<'NIXOS_CACHE'
["existing-linux"]
NIXOS_CACHE
printf 'old-hash\n' > "$TMP_DIR/cache/nixos-existing-linux.hash"

export PATH="$TMP_DIR/bin:$PATH"
export DRV_CACHE_DIR="$TMP_DIR/cache"
export DRV_CACHE_STAGING="$TMP_DIR/staging"
export DARWIN_CONFIGS='["existing-darwin","new-darwin"]'
export NIXOS_CONFIGS='["existing-linux","new-linux","new-arm"]'
export GITHUB_OUTPUT="$TMP_DIR/github-output"

failures=0
assert_output() {
  local key="$1" expected="$2"
  if grep -Fxq "$key=$expected" "$GITHUB_OUTPUT"; then
    echo "  PASS: $key reports $expected"
  else
    echo "  FAIL: $key did not report $expected"
    failures=$((failures + 1))
  fi
}

echo "=== CI Derivation Cache Tests ==="
if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: executable derivation cache helper does not exist: $SCRIPT"
  exit 1
fi
"$SCRIPT"
assert_output darwin-changed '["new-darwin"]'
assert_output nixos-changed '["new-linux"]'
assert_output nixos-arm-changed '["new-arm"]'

if [[ "$(cat "$DRV_CACHE_DIR/darwin-configs")" != "$DARWIN_CONFIGS" || \
      "$(cat "$DRV_CACHE_DIR/nixos-configs")" != "$NIXOS_CONFIGS" ]]; then
  echo "FAIL: current configuration lists were not persisted"
  failures=$((failures + 1))
else
  echo "  PASS: current configuration lists are persisted"
fi
if [[ "$(cat "$DRV_CACHE_DIR/darwin-new-darwin.hash")" != 'hash-new-darwin' ]]; then
  echo "FAIL: new Darwin derivation hash was not persisted"
  failures=$((failures + 1))
else
  echo "  PASS: new Darwin derivation hash is persisted"
fi
if [[ -e "$DRV_CACHE_STAGING" ]]; then
  echo "FAIL: staging directory remains after successful cache update"
  failures=$((failures + 1))
else
  echo "  PASS: cache staging is promoted atomically"
fi

: > "$GITHUB_OUTPUT"
CHANGED_HASH_FOR=existing-darwin "$SCRIPT"
assert_output darwin-changed '["existing-darwin"]'
echo "  PASS: a changed existing configuration is detected"

previous_configs="$(cat "$DRV_CACHE_DIR/darwin-configs")"
previous_hash="$(cat "$DRV_CACHE_DIR/darwin-new-darwin.hash")"
if FAIL_HASH_FOR=new-darwin "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: derivation hash errors should fail cache discovery"
  failures=$((failures + 1))
else
  echo "  PASS: derivation hash errors fail cache discovery"
fi
if [[ "$(cat "$DRV_CACHE_DIR/darwin-configs")" != "$previous_configs" || \
      "$(cat "$DRV_CACHE_DIR/darwin-new-darwin.hash")" != "$previous_hash" ]]; then
  echo "FAIL: failed update replaced the last valid cache"
  failures=$((failures + 1))
else
  echo "  PASS: failed update preserves the last valid cache"
fi

if ((failures > 0)); then
  echo "Results: $failures failure(s)"
  exit 1
fi
echo "Results: all derivation cache tests passed"
