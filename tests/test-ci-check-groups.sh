#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/.github/scripts/ci-checks.sh"
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
    printf '%s\n' '["core-packages","foundation-options","module-coverage","nixos-vector-enabled","onepassword-guard","overlay-openai-evals","overlay-rtk","vector-options","vm-packages","vm-role-developer","vm-role-foundation","vm-role-generator","vm-ssh","vm-ssh-target","vm-users"]'
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
run_plan() {
  : > "$GITHUB_OUTPUT"
  bash "$SCRIPT" plan "$1" "$2"
}

printf '%s\n' '=== CI check script tests ==='
run_plan pr '{"batchSize":3}'
assert_output matrix '{"include":[{"checks":["core-packages","foundation-options","nixos-vector-enabled"]},{"checks":["onepassword-guard","vector-options","vm-role-generator"]}]}'

run_plan extended '{"batchSize":5}'
assert_output matrix '{"include":[{"checks":["overlay-openai-evals","overlay-rtk"]}]}'

run_plan vm '{"batchSize":10}'
assert_output matrix '{"include":[{"checks":["vm-packages","vm-role-developer","vm-role-foundation","vm-ssh","vm-ssh-target","vm-users"]}]}'

run_plan vm-extended '{"batchSize":5}'
assert_output matrix '{"include":[{"checks":["vm-role-foundation","vm-role-developer"]}]}'

run_plan non-vm '{"batchSize":3,"checkPrefixes":["vector-","nixos-vector-"]}'
assert_output matrix '{"include":[{"checks":["nixos-vector-enabled","vector-options"]}]}'

run_plan non-vm '{"batchSize":20,"checkPrefixes":["no-such-check-prefix"]}'
assert_output matrix '{"include":[{"checks":["core-packages","foundation-options","module-coverage","nixos-vector-enabled","onepassword-guard","overlay-openai-evals","overlay-rtk","vector-options","vm-role-generator"]}]}'

: > "$MOCK_NIX_CALLS"
bash "$SCRIPT" build non-vm '{"checks":["vector-options","nixos-vector-enabled"],"maxJobs":2}'
assert_build_argument '--max-jobs'
assert_build_argument '2'
assert_build_argument '.#checks.x86_64-linux.vector-options'
assert_build_argument '.#checks.x86_64-linux.nixos-vector-enabled'
assert_not_build_argument '.#checks.x86_64-linux.core-packages'
assert_not_build_argument '.#checks.x86_64-linux.vm-users'

: > "$MOCK_NIX_CALLS"
bash "$SCRIPT" build non-vm '{"maxJobs":2}'
assert_build_argument '.#checks.x86_64-linux.overlay-rtk'
assert_build_argument '.#checks.x86_64-linux.module-coverage'
assert_build_argument '.#checks.x86_64-linux.vm-role-generator'
assert_not_build_argument '.#checks.x86_64-linux.vm-users'

: > "$MOCK_NIX_CALLS"
bash "$SCRIPT" build vm '{"maxJobs":2}'
assert_build_argument '.#checks.x86_64-linux.vm-users'
assert_build_argument '.#checks.x86_64-linux.vm-role-developer'
assert_build_argument '.#checks.x86_64-linux.vm-ssh-target'
assert_not_build_argument '.#checks.x86_64-linux.vm-role-generator'
assert_not_build_argument '.#checks.x86_64-linux.vector-options'

: > "$MOCK_NIX_CALLS"
bash "$SCRIPT" build pr '{"checks":["core-packages","foundation-options"],"maxJobs":2}'
assert_build_argument '.#checks.x86_64-linux.core-packages'
assert_build_argument '.#checks.x86_64-linux.foundation-options'
assert_not_build_argument '.#checks.x86_64-linux.module-coverage'

: > "$MOCK_NIX_CALLS"
bash "$SCRIPT" build extended '{"maxJobs":2}'
assert_build_argument '.#checks.x86_64-linux.overlay-openai-evals'
assert_build_argument '.#checks.x86_64-linux.overlay-rtk'
assert_not_build_argument '.#checks.x86_64-linux.core-packages'

: > "$MOCK_NIX_CALLS"
bash "$SCRIPT" build vm-extended '{"maxJobs":2}'
assert_build_argument '.#checks.x86_64-linux.vm-role-foundation'
assert_build_argument '.#checks.x86_64-linux.vm-role-developer'
assert_not_build_argument '.#checks.x86_64-linux.vm-users'

: > "$MOCK_NIX_CALLS"
bash "$SCRIPT" build vm-pr '{"maxJobs":2}'
assert_build_argument '.#checks.x86_64-linux.vm-users'
assert_build_argument '.#checks.x86_64-linux.vm-ssh'
assert_build_argument '.#checks.x86_64-linux.vm-packages'
assert_not_build_argument '.#checks.x86_64-linux.vm-role-developer'

: > "$MOCK_NIX_CALLS"
if bash "$SCRIPT" build pr '{"checks":["../untrusted"],"maxJobs":2}' >/dev/null 2>&1; then
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
printf '%s\n' 'Results: all CI check script tests passed'
