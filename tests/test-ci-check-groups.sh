#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/nix" <<'MOCK_NIX'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == eval ]]; then
  if [[ "$*" == *builtins.currentSystem* ]]; then
    printf '%s\n' 'x86_64-linux'
  elif [[ "$*" == *'.#checks.x86_64-linux'* ]]; then
    printf '%s\n' '["core-packages","foundation-options","module-coverage","onepassword-guard","overlay-openai-evals","overlay-rtk","vm-packages","vm-role-developer","vm-role-foundation","vm-ssh","vm-users"]'
  else
    echo "unexpected nix evaluation: $*" >&2
    exit 64
  fi
elif [[ "$1" == build ]]; then
  printf '%s\n' "$@" >> "$MOCK_NIX_CALLS"
else
  echo "unexpected nix command: $*" >&2
  exit 64
fi
MOCK_NIX
chmod +x "$TMP_DIR/bin/nix"
export NIX_BIN="$TMP_DIR/bin/nix"
export MOCK_NIX_CALLS="$TMP_DIR/nix-calls"
export GITHUB_OUTPUT="$TMP_DIR/github-output"
: > "$MOCK_NIX_CALLS"
: > "$GITHUB_OUTPUT"

failures=0
assert_output() {
  local name="$1" expected="$2"
  if grep -Fxq -- "$name=$expected" "$GITHUB_OUTPUT"; then
    echo "  PASS: $name matches expected output"
  else
    echo "  FAIL: $name did not match expected output"
    failures=$((failures + 1))
  fi
}
assert_build_argument() {
  local expected="$1"
  if grep -Fxq -- "$expected" "$MOCK_NIX_CALLS"; then
    echo "  PASS: build includes $expected"
  else
    echo "  FAIL: build is missing $expected"
    failures=$((failures + 1))
  fi
}
assert_not_build_argument() {
  local unexpected="$1"
  if grep -Fxq -- "$unexpected" "$MOCK_NIX_CALLS"; then
    echo "  FAIL: build unexpectedly includes $unexpected"
    failures=$((failures + 1))
  else
    echo "  PASS: build excludes $unexpected"
  fi
}

printf '%s\n' '=== CI check task tests ==='
devenv tasks run ci:checks:pr-plan --input batchSize=2
assert_output matrix '{"include":[{"checks":["core-packages","foundation-options"]},{"checks":["onepassword-guard"]}]}'

: > "$MOCK_NIX_CALLS"
devenv tasks run ci:checks:pr-shard --input-json '{"checks":["core-packages","foundation-options"],"maxJobs":2}'
assert_build_argument '--max-jobs'
assert_build_argument '2'
assert_build_argument '.#checks.x86_64-linux.core-packages'
assert_build_argument '.#checks.x86_64-linux.foundation-options'
assert_not_build_argument '.#checks.x86_64-linux.module-coverage'

: > "$MOCK_NIX_CALLS"
: > "$GITHUB_OUTPUT"
devenv tasks run ci:checks:extended
assert_build_argument '.#checks.x86_64-linux.overlay-openai-evals'
assert_build_argument '.#checks.x86_64-linux.overlay-rtk'
assert_not_build_argument '.#checks.x86_64-linux.core-packages'

: > "$MOCK_NIX_CALLS"
devenv tasks run ci:checks:vm-pr
assert_build_argument '.#checks.x86_64-linux.vm-users'
assert_build_argument '.#checks.x86_64-linux.vm-ssh'
assert_build_argument '.#checks.x86_64-linux.vm-packages'
assert_not_build_argument '.#checks.x86_64-linux.vm-role-developer'

: > "$MOCK_NIX_CALLS"
devenv tasks run ci:checks:vm-extended
assert_build_argument '.#checks.x86_64-linux.vm-role-foundation'
assert_build_argument '.#checks.x86_64-linux.vm-role-developer'
assert_not_build_argument '.#checks.x86_64-linux.vm-users'

: > "$MOCK_NIX_CALLS"
if devenv tasks run ci:checks:pr-shard --input-json '{"checks":["../untrusted"],"maxJobs":2}' >/dev/null 2>&1; then
  echo '  FAIL: invalid check names should be rejected'
  failures=$((failures + 1))
else
  echo '  PASS: invalid check names are rejected'
fi
if [[ -s "$MOCK_NIX_CALLS" ]]; then
  echo '  FAIL: invalid check name reached nix build'
  failures=$((failures + 1))
else
  echo '  PASS: invalid check name does not invoke nix build'
fi

if ((failures > 0)); then
  printf 'Results: %s failure(s)\n' "$failures"
  exit 1
fi
printf '%s\n' 'Results: all CI check task tests passed'
