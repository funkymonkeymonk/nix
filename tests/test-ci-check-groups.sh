#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/.github/scripts/build-checks.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/nix" <<'MOCK_NIX'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == eval ]]; then
  if [[ "$*" == *builtins.currentSystem* ]]; then
    printf '%s\n' "${MOCK_NIX_SYSTEM:-x86_64-linux}"
  else
    printf '%s\n' '["core-packages","foundation-packages","module-coverage","overlay-openai-evals","overlay-rtk","ste-linter-package","vm-packages","vm-role-developer","vm-role-foundation","vm-role-generator","vm-ssh","vm-users"]'
  fi
elif [[ "$1" == build ]]; then
  printf '%s\n' "$@" >> "$MOCK_NIX_CALLS"
else
  echo "unexpected nix command: $*" >&2
  exit 64
fi
MOCK_NIX
chmod +x "$TMP_DIR/nix"
export MOCK_NIX_CALLS="$TMP_DIR/nix-calls"
export NIX_BIN="$TMP_DIR/nix"

failures=0
assert_contains() {
  local expected="$1"
  if grep -Fxq -- "$expected" "$MOCK_NIX_CALLS"; then
    echo "  PASS: build includes $expected"
  else
    echo "  FAIL: build is missing $expected"
    failures=$((failures + 1))
  fi
}
assert_not_contains() {
  local unexpected="$1"
  if grep -Fxq -- "$unexpected" "$MOCK_NIX_CALLS"; then
    echo "  FAIL: build unexpectedly includes $unexpected"
    failures=$((failures + 1))
  else
    echo "  PASS: build excludes $unexpected"
  fi
}
run_group() {
  : > "$MOCK_NIX_CALLS"
  "$SCRIPT" "$1"
}

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: executable CI check selector does not exist: $SCRIPT"
  exit 1
fi

echo "=== CI Check Group Tests ==="
run_group pr
assert_contains '.#checks.x86_64-linux.core-packages'
assert_not_contains '.#checks.x86_64-linux.overlay-openai-evals'
assert_not_contains '.#checks.x86_64-linux.foundation-packages'
assert_not_contains '.#checks.x86_64-linux.module-coverage'
assert_contains '.#checks.x86_64-linux.vm-role-generator'
assert_not_contains '.#checks.x86_64-linux.vm-packages'
assert_not_contains '.#checks.x86_64-linux.vm-role-developer'

run_group extended
assert_contains '.#checks.x86_64-linux.overlay-openai-evals'
assert_contains '.#checks.x86_64-linux.overlay-rtk'
assert_contains '.#checks.x86_64-linux.foundation-packages'
assert_not_contains '.#checks.x86_64-linux.core-packages'

run_group vm-pr
assert_contains '.#checks.x86_64-linux.vm-users'
assert_contains '.#checks.x86_64-linux.vm-packages'
assert_not_contains '.#checks.x86_64-linux.vm-role-foundation'
assert_not_contains '.#checks.x86_64-linux.vm-role-developer'

run_group vm-extended
assert_contains '.#checks.x86_64-linux.vm-role-foundation'
assert_contains '.#checks.x86_64-linux.vm-role-developer'
assert_not_contains '.#checks.x86_64-linux.vm-users'

: > "$MOCK_NIX_CALLS"
if "$SCRIPT" invalid >/dev/null 2>&1; then
  echo "FAIL: unsupported check group was accepted"
  failures=$((failures + 1))
else
  echo "  PASS: unsupported check group is rejected"
fi
if [[ -s "$MOCK_NIX_CALLS" ]]; then
  echo "FAIL: unsupported group invoked nix build"
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  echo "Results: $failures failure(s)"
  exit 1
fi
echo "Results: all CI check group tests passed"
