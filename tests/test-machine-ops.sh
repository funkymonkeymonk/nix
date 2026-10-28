#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
machine_ops_script=${MACHINE_OPS_SCRIPT:-"$repo_root/scripts/machine-ops.sh"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/dotfile/machine-plans/plan-123" "$tmp/dotfile/machine-plans/plan-fleet" "$tmp/dotfile/machine-plans/plan-malformed"
export DEVENV_DOTFILE="$tmp/dotfile"
export MACHINE_OPS_TEST_LOG="$tmp/devenv.log"
export MACHINE_OPS_SECRETSPEC_LOG="$tmp/secretspec.log"
export PATH="$tmp/bin:$PATH"
: > "$MACHINE_OPS_TEST_LOG"
: > "$MACHINE_OPS_SECRETSPEC_LOG"

printf '#!%s\n' "$BASH" > "$tmp/bin/devenv"
cat >> "$tmp/bin/devenv" <<'MOCK'
[[ -z "${SECRETSPEC_PROFILE:-}" ]] || {
  echo 'SecretSpec profile leaked into global environment' >&2
  exit 93
}
printf 'devenv|%s\n' "$*" >> "$MACHINE_OPS_TEST_LOG"
MOCK

printf '#!%s\n' "$BASH" > "$tmp/bin/secretspec"
cat >> "$tmp/bin/secretspec" <<'MOCK'
printf 'secretspec|%s\n' "$*" >> "$MACHINE_OPS_SECRETSPEC_LOG"
[[ "${1:-}" == run && "${2:-}" == --profile && "${4:-}" == -- ]] || {
  echo "unexpected secretspec invocation: $*" >&2
  exit 90
}
shift 4
exec "$@"
MOCK

printf '#!%s\n' "$BASH" > "$tmp/bin/nix"
cat >> "$tmp/bin/nix" <<'MOCK'
# Only the catalog profile lookup used by the wrapper is mocked. No Nix build,
# network operation, devenv execution, or SecretSpec provider is run here.
[[ "${1:-}" == eval ]] || exit 91
[[ "${2:-}" == --impure && "${3:-}" == --raw && "${4:-}" == --expr ]] || {
  echo 'catalog metadata evaluation must allow the explicit local catalog path' >&2
  exit 94
}
secret_mode=${MACHINE_OPS_TEST_SECRET_MODE:-none}
case "$secret_mode" in
  none) secret_status=false; bootstrap_status=false ;;
  unrelated) secret_status=true; bootstrap_status=false ;;
  bootstrap) secret_status=true; bootstrap_status=true ;;
  *) exit 92 ;;
esac
case "${5:-}" in
  *zero*|*drlight*|*type-nas*|*type-server*|*type-server-arm*) printf '%s\t%s\t%s\t%s' Homelab nixos "$secret_status" "$bootstrap_status" ;;
  *MegamanX*) printf '%s\t%s\t%s\t%s' MegamanX darwin true false ;;
  *wweaver*|*darwin-server*) printf '%s\t%s\t%s\t%s' Personal darwin "$secret_status" "$bootstrap_status" ;;
  *bootstrap*|*type-desktop*|*installer-iso*) printf '%s\t%s\t%s\t%s' Personal nixos "$secret_status" "$bootstrap_status" ;;
  *) exit 92 ;;
esac
MOCK
chmod +x "$tmp/bin/devenv" "$tmp/bin/secretspec" "$tmp/bin/nix"

# Devenv 2.4 stores saved plans as JSON with a top-level machines map.
cat > "$tmp/dotfile/machine-plans/plan-123/plan.json" <<'JSON'
{"version":1,"scope":"machines","machines":{"zero":{"target":"zero-ssh"}}}
JSON
cat > "$tmp/dotfile/machine-plans/plan-fleet/plan.json" <<'JSON'
{"version":1,"scope":"machines","machines":{"zero":{},"drlight":{}}}
JSON
printf '{"version":1,"machines":' > "$tmp/dotfile/machine-plans/plan-malformed/plan.json"

run() {
  : > "$MACHINE_OPS_TEST_LOG"
  : > "$MACHINE_OPS_SECRETSPEC_LOG"
  DEVENV_BIN=devenv SECRETSPEC_BIN="$tmp/bin/secretspec" \
    MACHINE_OPS_TEST_SECRET_MODE="${MACHINE_OPS_TEST_SECRET_MODE:-none}" \
    bash "$machine_ops_script" "$@"
}
run_with_unrelated_secret() {
  MACHINE_OPS_TEST_SECRET_MODE=unrelated run "$@"
}
run_with_bootstrap_secret() {
  MACHINE_OPS_TEST_SECRET_MODE=bootstrap run "$@"
}
expect_log() {
  local expected=$1
  local actual
  actual=$(cat "$MACHINE_OPS_TEST_LOG")
  [[ "$actual" == "$expected" ]] || {
    printf 'expected devenv log:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    exit 1
  }
}
expect_profile() {
  local expected=$1
  grep -Fx "secretspec|run --profile $expected -- devenv ${2}" "$MACHINE_OPS_SECRETSPEC_LOG" >/dev/null || {
    printf 'expected scoped SecretSpec call for profile %s and devenv %s; got:\n' "$expected" "$2" >&2
    cat "$MACHINE_OPS_SECRETSPEC_LOG" >&2
    exit 1
  }
}
expect_rejected() {
  if run "$@" >"$tmp/output" 2>&1; then
    echo "expected command to be rejected: $*" >&2
    exit 1
  fi
  [[ ! -s "$MACHINE_OPS_TEST_LOG" ]] || {
    echo "rejected command still invoked devenv: $*" >&2
    cat "$MACHINE_OPS_TEST_LOG" >&2
    exit 1
  }
  [[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]] || {
    echo "rejected command still invoked SecretSpec: $*" >&2
    cat "$MACHINE_OPS_SECRETSPEC_LOG" >&2
    exit 1
  }
}

# Inventory inspection is the only operation allowed without a target and
# does not start a SecretSpec profile.
run info
expect_log 'devenv|machines info'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]

# Local builds use the documented build role path and are machine-specific.
run build zero
expect_log 'devenv|build machines.zero.build.nixos'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
run build wweaver
expect_log 'devenv|build machines.wweaver.build.nix-darwin'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]

# Every remote operation forwards exactly one explicit machine name and scopes
# SecretSpec to the profile recorded for that machine.
# Profiles with no declared secrets run non-destructive named operations
# without invoking SecretSpec or setting a global profile hint.
run check zero
expect_log 'devenv|machines check zero'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
run plan type-nas
expect_log 'devenv|machines plan type-nas'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
run check type-server
expect_log 'devenv|machines check type-server'
run plan type-server-arm
expect_log 'devenv|machines plan type-server-arm'
run deploy zero
expect_log 'devenv|machines deploy zero'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
run check MegamanX
expect_log 'devenv|machines check MegamanX'
expect_profile MegamanX 'machines check MegamanX'
run deploy MegamanX --use-machines-as-builders
expect_log 'devenv|machines deploy --use-machines-as-builders MegamanX'
expect_profile MegamanX 'machines deploy --use-machines-as-builders MegamanX'
! grep -q -- '--yes' "$MACHINE_OPS_TEST_LOG"

# Unrelated profile secrets do not satisfy the bootstrap prerequisite for install.
printf 'yes\n' | run_with_unrelated_secret install zero >"$tmp/install-unrelated-secret" 2>&1 && {
  echo 'install with only an unrelated secret unexpectedly succeeded' >&2
  exit 1
}
grep -F 'OPNIX_SERVICE_ACCOUNT_TOKEN' "$tmp/install-unrelated-secret" >/dev/null
grep -F 'cannot install zero' "$tmp/install-unrelated-secret" >/dev/null
[[ ! -s "$MACHINE_OPS_TEST_LOG" ]]
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]

# Only the exact semantic bootstrap secret allows install, and SecretSpec wraps
# only the explicitly named install operation.
printf 'yes\n' | run_with_bootstrap_secret install zero >"$tmp/install-bootstrap-secret" 2>&1
expect_profile Homelab 'machines install zero'
expect_log 'devenv|machines install zero'
[[ $(wc -l < "$MACHINE_OPS_SECRETSPEC_LOG") -eq 1 ]]
! grep -q -- '--yes' "$MACHINE_OPS_TEST_LOG"

# A saved single-machine plan is accepted from DEVENV_DOTFILE and the plan's
# verified machine supplies the profile used for the scoped apply.
run apply zero plan-123
expect_log 'devenv|machines apply plan-123'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
run_with_unrelated_secret apply zero plan-123
expect_log 'devenv|machines apply plan-123'
expect_profile Homelab 'machines apply plan-123'
[[ $(wc -l < "$MACHINE_OPS_SECRETSPEC_LOG") -eq 1 ]]

# Reject mismatched, fleet, malformed, and missing saved plans before either
# SecretSpec or devenv can see an apply request.
expect_rejected apply drlight plan-123
expect_rejected apply zero plan-fleet
expect_rejected apply zero plan-malformed
expect_rejected apply zero plan-missing
expect_rejected apply zero ../plan-123
expect_rejected apply zero /tmp/plan.json

# Install is destructive. Empty/default input cancels; even confirmation cannot
# proceed without a declared bootstrap secret. A declared profile can proceed.
printf '\n' | run install zero >"$tmp/install-warning" 2>&1 && {
  echo 'install without affirmative confirmation unexpectedly succeeded' >&2
  exit 1
}
grep -qi 'erase\|destroy\|wipe' "$tmp/install-warning"
[[ ! -s "$MACHINE_OPS_TEST_LOG" ]]
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
printf 'yes\n' | run install zero >"$tmp/install-no-secrets" 2>&1 && {
  echo 'install without a declared bootstrap secret unexpectedly succeeded' >&2
  exit 1
}
grep -F 'OPNIX_SERVICE_ACCOUNT_TOKEN' "$tmp/install-no-secrets" >/dev/null
[[ ! -s "$MACHINE_OPS_TEST_LOG" ]]
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]

# Missing, empty, malformed, and unknown targets never fall through to fleet
# defaults. No command other than info is allowed to receive an empty name.
expect_rejected build
expect_rejected build ''
expect_rejected check
expect_rejected plan
expect_rejected deploy
expect_rejected install ''
expect_rejected check unknown-machine
expect_rejected apply zero
expect_rejected deploy zero --yes

printf 'machine-ops safety tests passed\n'
