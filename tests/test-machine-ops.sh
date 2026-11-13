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
export MACHINE_OPS_SSH_LOG="$tmp/ssh.log"
export MACHINE_OPS_AUTHKEY_LOG="$tmp/authkey.log"
export MACHINE_OPS_KEY_CAPTURE="$tmp/staged-auth-key"
export MACHINE_OPS_REMOTE_KEY="$tmp/remote-tailscale-auth-key"
export MACHINE_OPS_STAGE_LOG="$tmp/key-stage.log"
export MACHINE_OPS_STAGE_SANDBOX="$tmp/remote-stage"
export MACHINE_OPS_STAGE_FAIL_BIN="$tmp/stage-fail-bin"
export MACHINE_OPS_TEST_ACTIVATION_MARKER="$tmp/activation-complete"
export MACHINE_OPS_TEST_TARGET_HOST="root@192.0.2.23"
export PATH="$tmp/bin:$PATH"
: > "$MACHINE_OPS_TEST_LOG"
: > "$MACHINE_OPS_SECRETSPEC_LOG"
: > "$MACHINE_OPS_SSH_LOG"
: > "$MACHINE_OPS_AUTHKEY_LOG"

printf '#!%s\n' "$BASH" > "$tmp/bin/devenv"
cat >> "$tmp/bin/devenv" <<'MOCK'
[[ -z "${SECRETSPEC_PROFILE:-}" ]] || {
  echo 'SecretSpec profile leaked into global environment' >&2
  exit 93
}
if [[ "${1:-}" == machines && "${2:-}" == info && -n "${3:-}" ]]; then
  printf '| Name | System | Target | Roles |\n'
  if [[ "$3" == MegamanX ]]; then
    printf '| %s | aarch64-darwin | %s | darwin |\n' "$3" "${MACHINE_OPS_TEST_TARGET_HOST_OVERRIDE:-monkey@192.0.2.82}"
  else
    printf '| %s | x86_64-linux | %s | nixos |\n' "$3" "${MACHINE_OPS_TEST_TARGET_HOST_OVERRIDE:-$MACHINE_OPS_TEST_TARGET_HOST}"
  fi
  printf 'devenv|%s\n' "$*" >> "$MACHINE_OPS_TEST_LOG"
  exit 0
fi
printf 'devenv|%s\n' "$*" >> "$MACHINE_OPS_TEST_LOG"
if [[ "${1:-}" == machines && ( "${2:-}" == deploy || "${2:-}" == apply ) ]]; then
  if [[ "${MACHINE_OPS_TEST_ACTIVATION_FAIL:-false}" == true ]]; then
    exit 42
  fi
  : > "$MACHINE_OPS_TEST_ACTIVATION_MARKER"
fi
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
if [[ "${5:-}" == 'builtins.currentSystem' ]]; then
  printf '%s' "${MACHINE_OPS_TEST_CURRENT_SYSTEM:-x86_64-linux}"
  exit
fi
secret_mode=${MACHINE_OPS_TEST_SECRET_MODE:-none}
case "$secret_mode" in
  none) secret_status=false; bootstrap_status=false ;;
  unrelated) secret_status=true; bootstrap_status=false ;;
  bootstrap|oauth) secret_status=true; bootstrap_status=true ;;
  *) exit 92 ;;
esac
emit_metadata() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$1" "$2" "$3" "$4" "${MACHINE_OPS_TEST_TARGET_SYSTEM_OVERRIDE:-$5}" \
    "${MACHINE_OPS_TEST_TAILSCALE_ENABLED_OVERRIDE:-$6}" \
    "${MACHINE_OPS_TEST_HAS_TAILSCALE_OAUTH:-false}" \
    "${MACHINE_OPS_TEST_TAILSCALE_TAGS_JSON:-$7}"
}
case "${5:-}" in
  *type-server-arm*) emit_metadata Opnix nixos "$secret_status" "$bootstrap_status" aarch64-linux false '[]' ;;
  *drlight*) emit_metadata Opnix nixos "$secret_status" "$bootstrap_status" x86_64-linux true '["tag:home-lab","tag:media-center"]' ;;
  *zero*|*type-nas*|*type-server*) emit_metadata Opnix nixos "$secret_status" "$bootstrap_status" x86_64-linux true '["tag:home-lab"]' ;;
  *MegamanX*) emit_metadata MegamanX darwin true false aarch64-darwin true '["tag:home-lab"]' ;;
  *wweaver*) emit_metadata Employee darwin "$secret_status" "$bootstrap_status" aarch64-darwin false '[]' ;;
  *Lydia*) emit_metadata Opnix darwin "$secret_status" "$bootstrap_status" aarch64-darwin false '[]' ;;
  *bootstrap*|*type-desktop*|*installer-iso*) emit_metadata Personal nixos "$secret_status" "$bootstrap_status" x86_64-linux false '[]' ;;
  *) exit 92 ;;
esac
MOCK
chmod +x "$tmp/bin/devenv" "$tmp/bin/secretspec" "$tmp/bin/nix"

printf '#!%s\n' "$BASH" > "$tmp/bin/ssh"
cat >> "$tmp/bin/ssh" <<'MOCK'
remote_command="${!#}"
printf 'ssh|%s\n' "$*" >> "$MACHINE_OPS_SSH_LOG"
case "$remote_command" in
  *"tailscale status --json"*)
    [[ "${MACHINE_OPS_TEST_STATUS_FAILURE:-false}" != true ]] || exit 96
    if [[ -f "$MACHINE_OPS_TEST_ACTIVATION_MARKER" ]]; then
      printf 'wait-status|%s\n' "$remote_command" >> "$MACHINE_OPS_STAGE_LOG"
      printf '{"BackendState":"%s"}\n' "${MACHINE_OPS_TEST_POST_BACKEND_STATE:-Running}"
    elif [[ "${MACHINE_OPS_TEST_STATUS_EMPTY:-false}" == true ]]; then
      :
    elif [[ "${MACHINE_OPS_TEST_STATUS_MALFORMED:-false}" == true ]]; then
      printf '{malformed-json}\n'
    elif [[ -n "${MACHINE_OPS_TEST_STATUS_JSON:-}" ]]; then
      printf '%s\n' "$MACHINE_OPS_TEST_STATUS_JSON"
    else
      printf '{"BackendState":"%s"}\n' "${MACHINE_OPS_TEST_BACKEND_STATE:-NeedsLogin}"
    fi
    ;;
  *"cat >"*)
    if [[ "${MACHINE_OPS_TEST_STAGE_WRITE_FAILURE:-false}" == true ]]; then
      mkdir -p "$MACHINE_OPS_STAGE_SANDBOX" "$MACHINE_OPS_STAGE_FAIL_BIN"
      printf '#!%s\n' "$BASH" > "$MACHINE_OPS_STAGE_FAIL_BIN/cat"
      cat >> "$MACHINE_OPS_STAGE_FAIL_BIN/cat" <<'FAIL_CAT'
printf partial
exit 97
FAIL_CAT
      chmod +x "$MACHINE_OPS_STAGE_FAIL_BIN/cat"
      stage_command=${remote_command//\/run\/devenv/$MACHINE_OPS_STAGE_SANDBOX\/run}
      stage_command=${stage_command//\/tmp\/devenv-tailscale-auth-key/$MACHINE_OPS_STAGE_SANDBOX\/darwin-auth-key}
      PATH="$MACHINE_OPS_STAGE_FAIL_BIN:$PATH" "$BASH" -c "$stage_command" </dev/null
      exit $?
    fi
    [[ "${MACHINE_OPS_TEST_STAGE_FAILURE:-false}" != true ]] || exit 97
    cat > "$MACHINE_OPS_REMOTE_KEY"
    cp "$MACHINE_OPS_REMOTE_KEY" "$MACHINE_OPS_KEY_CAPTURE"
    chmod 0600 "$MACHINE_OPS_REMOTE_KEY"
    printf 'staged|%s\n' "$remote_command" >> "$MACHINE_OPS_STAGE_LOG"
    ;;
  *"rm -f"*"/run/devenv/tailscale-auth-key"*|*"rm -f"*"/tmp/devenv-tailscale-auth-key"*)
    rm -f "$MACHINE_OPS_REMOTE_KEY" \
      "$MACHINE_OPS_STAGE_SANDBOX/run/tailscale-auth-key" \
      "$MACHINE_OPS_STAGE_SANDBOX/darwin-auth-key" \
      "$MACHINE_OPS_STAGE_SANDBOX"/darwin-auth-key.*
    printf 'cleaned|%s\n' "$remote_command" >> "$MACHINE_OPS_STAGE_LOG"
    ;;
  *) echo "Unexpected SSH remote command" >&2; exit 95 ;;
esac
MOCK
printf '#!%s\n' "$BASH" > "$tmp/bin/tailscale-authkey"
cat >> "$tmp/bin/tailscale-authkey" <<'MOCK'
printf 'tailscale-authkey|%s\n' "$*" >> "$MACHINE_OPS_AUTHKEY_LOG"
printf '%s' 'fake-one-time-auth-key'
MOCK
printf '#!%s\n' "$BASH" > "$tmp/bin/sleep"
cat >> "$tmp/bin/sleep" <<'MOCK'
exit 0
MOCK
chmod +x "$tmp/bin/ssh" "$tmp/bin/tailscale-authkey" "$tmp/bin/sleep"

# Devenv 2.4 stores saved plans as JSON with a top-level machines map.
cat > "$tmp/dotfile/machine-plans/plan-123/plan.json" <<'JSON'
{"version":1,"scope":"machines","machines":{"zero":{"target":"zero-ssh"}}}
JSON
cat > "$tmp/dotfile/machine-plans/plan-fleet/plan.json" <<'JSON'
{"version":1,"scope":"machines","machines":{"zero":{},"drlight":{}}}
JSON
printf '{"version":1,"machines":' > "$tmp/dotfile/machine-plans/plan-malformed/plan.json"
mkdir -p "$tmp/dotfile/machine-plans/plan-megamanx"
cat > "$tmp/dotfile/machine-plans/plan-megamanx/plan.json" <<'JSON'
{"version":1,"scope":"machines","machines":{"MegamanX":{"target":"mac-ssh"}}}
JSON

run() {
  : > "$MACHINE_OPS_TEST_LOG"
  : > "$MACHINE_OPS_SECRETSPEC_LOG"
  : > "$MACHINE_OPS_SSH_LOG"
  : > "$MACHINE_OPS_AUTHKEY_LOG"
  : > "$MACHINE_OPS_STAGE_LOG"
  rm -f "$MACHINE_OPS_REMOTE_KEY" "$MACHINE_OPS_TEST_ACTIVATION_MARKER"
  : > "$MACHINE_OPS_KEY_CAPTURE"
  DEVENV_BIN=devenv SECRETSPEC_BIN="$tmp/bin/secretspec" \
    SSH_BIN="$tmp/bin/ssh" TAILSCALE_AUTHKEY_SCRIPT="$tmp/bin/tailscale-authkey" \
    MACHINE_OPS_TEST_SECRET_MODE="${MACHINE_OPS_TEST_SECRET_MODE:-none}" \
    bash "$machine_ops_script" "$@"
}
run_with_unrelated_secret() {
  MACHINE_OPS_TEST_SECRET_MODE=unrelated run "$@"
}
run_with_bootstrap_secret() {
  MACHINE_OPS_TEST_SECRET_MODE=bootstrap run "$@"
}
run_with_oauth() {
  MACHINE_OPS_TEST_SECRET_MODE=oauth \
    MACHINE_OPS_TEST_HAS_TAILSCALE_OAUTH=true \
    run "$@"
}
run_for_system() {
  local system=$1
  shift
  MACHINE_OPS_TEST_CURRENT_SYSTEM=$system run "$@"
}
expect_rejected_for_system() {
  local system=$1
  shift
  if MACHINE_OPS_TEST_CURRENT_SYSTEM=$system run "$@" >"$tmp/invalid-system-output" 2>&1; then
    echo "expected invalid Nix system to be rejected: $system" >&2
    exit 1
  fi
  [[ ! -s "$MACHINE_OPS_TEST_LOG" ]] || {
    echo "invalid Nix system still invoked devenv: $system" >&2
    cat "$MACHINE_OPS_TEST_LOG" >&2
    exit 1
  }
  [[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]] || {
    echo "invalid Nix system still invoked SecretSpec: $system" >&2
    cat "$MACHINE_OPS_SECRETSPEC_LOG" >&2
    exit 1
  }
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
expect_no_secret_resolution() {
  [[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]] || {
    echo 'operation resolved a SecretSpec profile it does not consume' >&2
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
expect_oauth_state_rejected() {
  local expected=$1
  shift
  if run_with_oauth "$@" >"$tmp/oauth-state-error" 2>&1; then
    echo "expected unsafe Tailscale state to reject OAuth deployment: $*" >&2
    exit 1
  fi
  grep -F "$expected" "$tmp/oauth-state-error" >/dev/null || {
    echo "missing fail-closed error for OAuth deployment: $*" >&2
    cat "$tmp/oauth-state-error" >&2
    exit 1
  }
  if grep -Eq 'devenv\|machines (deploy|apply)' "$MACHINE_OPS_TEST_LOG"; then
    echo "unsafe Tailscale state still activated a machine: $*" >&2
    cat "$MACHINE_OPS_TEST_LOG" >&2
    exit 1
  fi
  [[ ! -s "$MACHINE_OPS_AUTHKEY_LOG" && ! -e "$MACHINE_OPS_REMOTE_KEY" ]] || {
    echo "unsafe Tailscale state still generated or staged a key: $*" >&2
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
run_with_oauth deploy zero
expect_log $'devenv|machines info zero\ndevenv|machines deploy zero'
grep -F 'secretspec|run --profile Opnix -- '"$tmp/bin/tailscale-authkey"' zero ["tag:home-lab"]' "$MACHINE_OPS_SECRETSPEC_LOG" >/dev/null
[[ $(cat "$MACHINE_OPS_KEY_CAPTURE") == 'fake-one-time-auth-key' ]]
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
grep -q '^wait-status|' "$MACHINE_OPS_STAGE_LOG"
grep -q '^cleaned|' "$MACHINE_OPS_STAGE_LOG"
grep -F 'chmod 0600 /run/devenv/tailscale-auth-key' "$MACHINE_OPS_STAGE_LOG" >/dev/null
run_with_oauth deploy zero --yes
expect_log $'devenv|machines info zero\ndevenv|machines deploy --yes zero'
[[ -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
# The explicitly disabled server target never generates or stages a key.
run deploy type-server-arm
expect_log 'devenv|machines deploy type-server-arm'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
[[ ! -s "$MACHINE_OPS_SSH_LOG" ]]

# OAuth-backed deployment creates a one-time Tailscale key only when the
# target is not already authenticated, stages it over SSH, and never logs it.
MACHINE_OPS_TEST_SECRET_MODE=oauth \
MACHINE_OPS_TEST_HAS_TAILSCALE_OAUTH=true \
MACHINE_OPS_TEST_TAILSCALE_TAGS_JSON='["tag:home-lab","tag:media-center"]' \
run deploy drlight --yes
expect_log $'devenv|machines info drlight\ndevenv|machines deploy --yes drlight'
grep -F 'secretspec|run --profile Opnix -- '"$tmp/bin/tailscale-authkey"' drlight ["tag:home-lab","tag:media-center"]' "$MACHINE_OPS_SECRETSPEC_LOG" >/dev/null
grep -F 'tailscale-authkey|drlight ["tag:home-lab","tag:media-center"]' "$MACHINE_OPS_AUTHKEY_LOG" >/dev/null
[[ $(cat "$MACHINE_OPS_KEY_CAPTURE") == 'fake-one-time-auth-key' ]]
grep -F 'root@192.0.2.23' "$MACHINE_OPS_SSH_LOG" >/dev/null
if grep -F 'fake-one-time-auth-key' "$MACHINE_OPS_TEST_LOG" "$MACHINE_OPS_SECRETSPEC_LOG" "$MACHINE_OPS_SSH_LOG" "$MACHINE_OPS_AUTHKEY_LOG"; then
  echo 'one-time Tailscale auth key leaked to command logs' >&2
  exit 1
fi

# An already authenticated node does not create or stage an unused key.
MACHINE_OPS_TEST_SECRET_MODE=oauth \
MACHINE_OPS_TEST_HAS_TAILSCALE_OAUTH=true \
MACHINE_OPS_TEST_TAILSCALE_TAGS_JSON='["tag:home-lab","tag:media-center"]' \
MACHINE_OPS_TEST_BACKEND_STATE=Running \
run deploy drlight --yes
expect_log $'devenv|machines info drlight\ndevenv|machines deploy --yes drlight'
[[ ! -s "$MACHINE_OPS_AUTHKEY_LOG" ]]
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
run check MegamanX
expect_log 'devenv|machines check MegamanX'
expect_profile MegamanX 'machines check MegamanX'
run_with_unrelated_secret check wweaver
expect_log 'devenv|machines check wweaver'
expect_profile Employee 'machines check wweaver'

# Unknown, malformed, or failed status checks fail before key generation or
# activation. Only the known NeedsLogin state may consume an OAuth key.
MACHINE_OPS_TEST_BACKEND_STATE=NoState expect_oauth_state_rejected 'Tailscale backend state' deploy zero
MACHINE_OPS_TEST_STATUS_JSON='{}' expect_oauth_state_rejected 'Tailscale backend state' deploy zero
MACHINE_OPS_TEST_STATUS_EMPTY=true expect_oauth_state_rejected 'unable to inspect a valid Tailscale backend state' deploy zero
MACHINE_OPS_TEST_STATUS_MALFORMED=true expect_oauth_state_rejected 'unable to inspect a valid Tailscale backend state' deploy zero
MACHINE_OPS_TEST_STATUS_FAILURE=true expect_oauth_state_rejected 'unable to inspect a valid Tailscale backend state' deploy zero
MACHINE_OPS_TEST_SECRET_MODE=oauth MACHINE_OPS_TEST_HAS_TAILSCALE_OAUTH=false run deploy zero >"$tmp/missing-oauth-profile" 2>&1 && {
  echo 'deployment without OAuth credentials unexpectedly succeeded' >&2
  exit 1
}
grep -F 'lacks the OAuth client ID and secret' "$tmp/missing-oauth-profile" >/dev/null
[[ ! -s "$MACHINE_OPS_AUTHKEY_LOG" && ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
MACHINE_OPS_TEST_SECRET_MODE=oauth MACHINE_OPS_TEST_HAS_TAILSCALE_OAUTH=true MACHINE_OPS_TEST_TAILSCALE_TAGS_JSON='[]' run deploy zero >"$tmp/missing-oauth-tags" 2>&1 && {
  echo 'deployment without OAuth tags unexpectedly succeeded' >&2
  exit 1
}
grep -F 'no configured Tailscale OAuth tags' "$tmp/missing-oauth-tags" >/dev/null
[[ ! -s "$MACHINE_OPS_AUTHKEY_LOG" && ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
MACHINE_OPS_TEST_STAGE_FAILURE=true run_with_oauth deploy zero >"$tmp/stage-failure" 2>&1 && {
  echo 'deployment after key staging failure unexpectedly succeeded' >&2
  exit 1
}
if grep -Eq 'devenv\\|machines deploy zero' "$MACHINE_OPS_TEST_LOG"; then
  echo 'key staging failure activated the target' >&2
  exit 1
fi
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]

# A remote cat that writes partial data and then fails must fail the SSH stage,
# even though later chmod/mv commands would succeed without set -e. Verify both
# platform commands fail closed and no activation occurs.
for stage_machine in zero MegamanX; do
  rm -rf "$MACHINE_OPS_STAGE_SANDBOX"
  if [[ "$stage_machine" == MegamanX ]]; then
    MACHINE_OPS_TEST_TARGET_HOST_OVERRIDE=monkey@192.0.2.82 \
      MACHINE_OPS_TEST_STAGE_WRITE_FAILURE=true run_with_oauth deploy "$stage_machine" >"$tmp/stage-write-failure-$stage_machine" 2>&1 && {
      echo "$stage_machine deployment after a remote write failure unexpectedly succeeded" >&2
      exit 1
    }
  else
    MACHINE_OPS_TEST_STAGE_WRITE_FAILURE=true run_with_oauth deploy "$stage_machine" >"$tmp/stage-write-failure-$stage_machine" 2>&1 && {
      echo "$stage_machine deployment after a remote write failure unexpectedly succeeded" >&2
      exit 1
    }
  fi
  if grep -F 'machines deploy' "$MACHINE_OPS_TEST_LOG"; then
    echo "$stage_machine activated after a remote auth-key write failure" >&2
    exit 1
  fi
  [[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
  [[ ! -e "$MACHINE_OPS_STAGE_SANDBOX/run/tailscale-auth-key" ]]
  [[ ! -e "$MACHINE_OPS_STAGE_SANDBOX/darwin-auth-key" ]]
done
MACHINE_OPS_TEST_ACTIVATION_FAIL=true run_with_oauth deploy zero >"$tmp/activation-failure" 2>&1 && {
  echo 'failed activation unexpectedly succeeded' >&2
  exit 1
}
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
MACHINE_OPS_TEST_ACTIVATION_FAIL=true run_with_oauth apply zero plan-123 >"$tmp/apply-activation-failure" 2>&1 && {
  echo 'failed apply activation unexpectedly succeeded' >&2
  exit 1
}
grep -Fx 'devenv|machines info zero' "$MACHINE_OPS_TEST_LOG" >/dev/null
grep -Fx 'devenv|machines apply plan-123' "$MACHINE_OPS_TEST_LOG" >/dev/null
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
MACHINE_OPS_TEST_POST_BACKEND_STATE=NeedsLogin run_with_oauth deploy zero >"$tmp/auth-timeout" 2>&1 && {
  echo 'deployment succeeded without tailnet authentication' >&2
  exit 1
}
grep -F 'did not reach Tailscale BackendState=Running' "$tmp/auth-timeout" >/dev/null
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]

# A reviewed NixOS apply uses the same one-time key flow and waits for Running.
run_with_oauth apply zero plan-123
expect_log $'devenv|machines info zero\ndevenv|machines apply plan-123'
expect_profile Opnix 'machines apply plan-123'
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
grep -q '^wait-status|' "$MACHINE_OPS_STAGE_LOG"
MACHINE_OPS_TEST_BACKEND_STATE=Running run_with_oauth apply zero plan-123
expect_log $'devenv|machines info zero\ndevenv|machines apply plan-123'
[[ ! -s "$MACHINE_OPS_AUTHKEY_LOG" && ! -e "$MACHINE_OPS_REMOTE_KEY" ]]

# Darwin deploy/apply stage the key to the launchd-watched /tmp path and use
# MegamanX's scoped OAuth profile.
MACHINE_OPS_TEST_TARGET_HOST_OVERRIDE=monkey@192.0.2.82 run_with_oauth deploy MegamanX
expect_log $'devenv|machines info MegamanX\ndevenv|machines deploy MegamanX'
grep -F 'secretspec|run --profile MegamanX -- '"$tmp/bin/tailscale-authkey"' MegamanX ["tag:home-lab"]' "$MACHINE_OPS_SECRETSPEC_LOG" >/dev/null
grep -F 'tailscale-authkey|MegamanX ["tag:home-lab"]' "$MACHINE_OPS_AUTHKEY_LOG" >/dev/null
grep -F '/tmp/devenv-tailscale-auth-key' "$MACHINE_OPS_STAGE_LOG" >/dev/null
grep -F 'chmod 0600 "$tmp"' "$MACHINE_OPS_STAGE_LOG" >/dev/null
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
MACHINE_OPS_TEST_TARGET_HOST_OVERRIDE=monkey@192.0.2.82 run_with_oauth apply MegamanX plan-megamanx
expect_log $'devenv|machines info MegamanX\ndevenv|machines apply plan-megamanx'
expect_profile MegamanX 'machines apply plan-megamanx'
grep -F '/tmp/devenv-tailscale-auth-key' "$MACHINE_OPS_STAGE_LOG" >/dev/null
grep -F 'chmod 0600 "$tmp"' "$MACHINE_OPS_STAGE_LOG" >/dev/null
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]

if grep -F 'fake-one-time-auth-key' "$MACHINE_OPS_TEST_LOG" "$MACHINE_OPS_SECRETSPEC_LOG" "$MACHINE_OPS_SSH_LOG" "$MACHINE_OPS_AUTHKEY_LOG"; then
  echo 'one-time Tailscale auth key leaked to command logs' >&2
  exit 1
fi

# Automatic deploy uses a local build when the full Nix system IDs match and
# asks Devenv to select matching remote builders when they differ.
MACHINE_OPS_TEST_CURRENT_SYSTEM=x86_64-linux run_with_oauth deploy-auto zero
expect_log $'devenv|machines info zero\ndevenv|machines deploy zero'
[[ -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
MACHINE_OPS_TEST_TARGET_HOST_OVERRIDE=monkey@192.0.2.82 MACHINE_OPS_TEST_CURRENT_SYSTEM=x86_64-linux run_with_oauth deploy-auto MegamanX
expect_log $'devenv|machines info MegamanX\ndevenv|machines deploy --use-machines-as-builders MegamanX'
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
MACHINE_OPS_TEST_TARGET_HOST_OVERRIDE=monkey@192.0.2.82 MACHINE_OPS_TEST_CURRENT_SYSTEM=aarch64-darwin run_with_oauth deploy-auto MegamanX
expect_log $'devenv|machines info MegamanX\ndevenv|machines deploy MegamanX'
[[ ! -e "$MACHINE_OPS_REMOTE_KEY" ]]
run_for_system x86_64-linux deploy-auto type-server-arm
expect_log 'devenv|machines deploy --use-machines-as-builders type-server-arm'
expect_rejected_for_system unknown-system deploy-auto MegamanX
MACHINE_OPS_TEST_TARGET_SYSTEM_OVERRIDE=unknown-system expect_rejected_for_system x86_64-linux deploy-auto MegamanX
if grep -q -- '--yes' "$MACHINE_OPS_TEST_LOG"; then
  echo 'automatic deploy unexpectedly bypassed interactive confirmation' >&2
  exit 1
fi

# Unrelated profile secrets do not satisfy the bootstrap prerequisite for install.
printf 'yes\n' | run_with_unrelated_secret install zero >"$tmp/install-unrelated-secret" 2>&1 && {
  echo 'install with only an unrelated secret unexpectedly succeeded' >&2
  exit 1
}
grep -F 'OPNIX_SERVICE_ACCOUNT_TOKEN' "$tmp/install-unrelated-secret" >/dev/null
grep -F 'cannot install zero' "$tmp/install-unrelated-secret" >/dev/null
[[ ! -s "$MACHINE_OPS_TEST_LOG" ]]
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]

# Install passes the selected profile to Devenv's bootstrap resolver, which
# writes the secret to the target without exposing it through a shell wrapper.
printf 'yes\n' | run_with_bootstrap_secret install zero >"$tmp/install-bootstrap-secret" 2>&1
expect_log 'devenv|machines install zero --secretspec-profile Opnix'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
if grep -q -- '--yes' "$MACHINE_OPS_TEST_LOG"; then
  echo 'install unexpectedly bypassed interactive confirmation' >&2
  exit 1
fi

# A saved single-machine plan is accepted from DEVENV_DOTFILE and the plan's
# verified machine supplies the profile used for the scoped apply.
MACHINE_OPS_TEST_BACKEND_STATE=Running run apply zero plan-123
expect_log $'devenv|machines info zero\ndevenv|machines apply plan-123'
[[ ! -s "$MACHINE_OPS_SECRETSPEC_LOG" ]]
MACHINE_OPS_TEST_BACKEND_STATE=Running run_with_unrelated_secret apply zero plan-123
expect_log $'devenv|machines info zero\ndevenv|machines apply plan-123'
expect_profile Opnix 'machines apply plan-123'
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
expect_rejected deploy-auto
expect_rejected install ''
expect_rejected check unknown-machine
expect_rejected apply zero
expect_rejected deploy zero --bogus

printf 'machine-ops safety tests passed\n'
