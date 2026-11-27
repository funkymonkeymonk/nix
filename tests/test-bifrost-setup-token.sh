#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; printf "Bifrost setup-token harness failed at line %s (status %s)\\n" "$LINENO" "$status" >&2' ERR

[[ "${BIFROST_SETUP_TASK_VALID:-false}" == true ]] || {
  echo 'FAIL: setup-token task must require confirm=true and invoke its creator' >&2
  exit 1
}
[[ -n "${BIFROST_SETUP_SCRIPT:-}" && -f "$BIFROST_SETUP_SCRIPT" ]] || {
  echo 'FAIL: Bifrost setup-token creator script is missing' >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/bifrost-setup-token-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/secure-temp" "$tmp/task-root/scripts"
if [[ -n "${BIFROST_SETUP_BASH_BIN:-}" ]]; then
  export PATH="$(dirname "$BIFROST_SETUP_BASH_BIN"):$tmp/bin:$PATH"
else
  export PATH="$tmp/bin:$PATH"
fi
export BIFROST_SETUP_TMPDIR="$tmp/secure-temp"
export BIFROST_SETUP_OP_LOG="$tmp/op.log"
export BIFROST_SETUP_OPENSSL_LOG="$tmp/openssl.log"
export BIFROST_SETUP_NIX_LOG="$tmp/nix.log"
export BIFROST_SETUP_CAPTURE="$tmp/generated-token"
export BIFROST_SETUP_TEMPLATE_SOURCE="$tmp/api-credential-template.json"
export BIFROST_SETUP_TEST_DEFAULT_VAULT='Opnix'
export BIFROST_SETUP_TEST_EXISTING='false'
export BIFROST_SETUP_TEST_ARCHIVED='false'
export BIFROST_SETUP_TEST_FAILURE=''
export BIFROST_SETUP_TEST_RANDOM_HEX='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
: > "$BIFROST_SETUP_OP_LOG"
: > "$BIFROST_SETUP_OPENSSL_LOG"
: > "$BIFROST_SETUP_NIX_LOG"
cp "$BIFROST_SETUP_SCRIPT" "$tmp/task-root/scripts/create-bifrost-setup-token.sh"

cat > "$BIFROST_SETUP_TEMPLATE_SOURCE" <<'JSON'
{"title":"","category":"API_CREDENTIAL","fields":[{"id":"credential","type":"CONCEALED","label":"credential","value":""}]}
JSON

cat > "$tmp/bin/nix" <<'MOCK'
#!/usr/bin/env bash
printf 'nix|%s\n' "$*" >> "$BIFROST_SETUP_NIX_LOG"
[[ "$*" == 'eval --impure --raw .#darwinConfigurations.MegamanX.config.myConfig.onepassword.defaultVault' ]] || exit 90
printf '%s' "$BIFROST_SETUP_TEST_DEFAULT_VAULT"
MOCK
cat > "$tmp/bin/openssl" <<'MOCK'
#!/usr/bin/env bash
printf 'openssl|%s\n' "$*" >> "$BIFROST_SETUP_OPENSSL_LOG"
[[ "$*" == 'rand -hex 32' && "$BIFROST_SETUP_TEST_FAILURE" != openssl ]] || exit 91
printf '%s\n' "$BIFROST_SETUP_TEST_RANDOM_HEX"
MOCK
cat > "$tmp/bin/op" <<'MOCK'
#!/usr/bin/env bash
printf 'op|%s\n' "$*" >> "$BIFROST_SETUP_OP_LOG"
[[ "$1" == item ]] || exit 92
case "$2" in
  list)
    [[ "$*" == 'list --include-archive --vault Opnix --format json' || "$*" == "list --include-archive --vault $BIFROST_SETUP_TEST_DEFAULT_VAULT --format json" ]] || exit 93
    [[ "$BIFROST_SETUP_TEST_FAILURE" != list ]] || exit 94
    if [[ "$BIFROST_SETUP_TEST_ARCHIVED" == true ]]; then
      printf '[{"title":"Bifrost Setup Token","state":"ARCHIVED"}]\n'
    elif [[ "$BIFROST_SETUP_TEST_EXISTING" == true ]]; then
      printf '[{"title":"Bifrost Setup Token"}]\n'
    else
      printf '[]\n'
    fi
    ;;
  template)
    [[ "$3" == get && "$4" == 'API Credential' ]] || exit 95
    [[ "$BIFROST_SETUP_TEST_FAILURE" != template ]] || exit 96
    cat "$BIFROST_SETUP_TEMPLATE_SOURCE"
    ;;
  create)
    template=''
    vault=''
    shift 2
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --vault) vault=$2; shift 2 ;;
        --template) template=$2; shift 2 ;;
        *) exit 97 ;;
      esac
    done
    [[ "$BIFROST_SETUP_TEST_FAILURE" != create ]] || {
      printf 'mock create response leaked %s\n' "$BIFROST_SETUP_TEST_RANDOM_HEX" >&2
      exit 98
    }
    [[ "$vault" == "$BIFROST_SETUP_TEST_DEFAULT_VAULT" && -f "$template" ]] || exit 99
    [[ "$(stat -c '%a' "$template")" == 600 ]] || exit 100
    template_dir=$(dirname "$template")
    [[ "$(stat -c '%a' "$template_dir")" == 700 ]] || exit 101
    [[ "$(stat -c '%a' "$template_dir/random.hex")" == 600 ]] || exit 102
    [[ "$(stat -c '%a' "$template_dir/api-credential-template.json")" == 600 ]] || exit 103
    jq -e '.title == "Bifrost Setup Token" and .category == "API_CREDENTIAL" and any(.fields[]; .id == "credential" and .type == "CONCEALED")' "$template" >/dev/null || exit 104
    jq -er '.fields[] | select(.id == "credential") | .value' "$template" > "$BIFROST_SETUP_CAPTURE"
    token=$(cat "$BIFROST_SETUP_CAPTURE")
    [[ "$token" =~ ^[0-9a-f]{64}$ ]] || exit 105
    while IFS= read -r environment_name; do
      environment_value=${!environment_name}
      [[ "$environment_value" != *"$token"* ]] || exit 106
    done < <(compgen -e)
    printf 'created setup token: %s\n' "$token"
    ;;
  *) exit 107 ;;
esac
MOCK
chmod +x "$tmp/bin/nix" "$tmp/bin/openssl" "$tmp/bin/op"

run_creator() {
  NIX_BIN="$tmp/bin/nix" OPENSSL_BIN="$tmp/bin/openssl" OP_BIN="$tmp/bin/op" \
    "${BIFROST_SETUP_BASH_BIN:-bash}" "$BIFROST_SETUP_SCRIPT" "$@"
}
run_task() {
  local input=$1
  (
    cd "$tmp/task-root"
    NIX_BIN="$tmp/bin/nix" OP_BIN="$tmp/bin/op" DEVENV_TASK_INPUT="$input" \
      "${BIFROST_SETUP_BASH_BIN:-bash}" "$BIFROST_SETUP_TASK_EXEC_SCRIPT"
  )
}

if run_creator >"$tmp/no-confirm.out" 2>"$tmp/no-confirm.err"; then
  echo 'setup-token creator unexpectedly ran without confirmation' >&2
  exit 1
fi
for input in '{}' '{"confirm":false}'; do
  if run_task "$input" >"$tmp/task-no-confirm.out" 2>"$tmp/task-no-confirm.err"; then
    echo 'setup-token task unexpectedly accepted missing or false confirmation' >&2
    exit 1
  fi
  [[ ! -s "$BIFROST_SETUP_OP_LOG" && ! -s "$BIFROST_SETUP_OPENSSL_LOG" && ! -s "$BIFROST_SETUP_NIX_LOG" ]]
done

if run_task '{"confirm":true}' >"$tmp/create.out" 2>"$tmp/create.err"; then
  :
else
  status=$?
  cat "$tmp/create.err" >&2
  exit "$status"
fi
token=$(cat "$BIFROST_SETUP_CAPTURE")
[[ "$token" =~ ^[0-9a-f]{64}$ ]]
if grep -Fq "$token" "$tmp/create.out" "$tmp/create.err" "$BIFROST_SETUP_OP_LOG" "$BIFROST_SETUP_OPENSSL_LOG" "$BIFROST_SETUP_NIX_LOG"; then
  echo 'generated Bifrost setup token leaked to output or logs' >&2
  exit 1
fi
grep -F 'op|item list --include-archive --vault Opnix --format json' "$BIFROST_SETUP_OP_LOG" >/dev/null
grep -F 'op|item create --vault Opnix --template ' "$BIFROST_SETUP_OP_LOG" >/dev/null
grep -F 'nix|eval --impure --raw .#darwinConfigurations.MegamanX.config.myConfig.onepassword.defaultVault' "$BIFROST_SETUP_NIX_LOG" >/dev/null
[[ -z "$(find "$BIFROST_SETUP_TMPDIR" -mindepth 1 -print -quit)" ]]

for existing_mode in active archived; do
  : > "$BIFROST_SETUP_OPENSSL_LOG"
  : > "$BIFROST_SETUP_OP_LOG"
  if [[ "$existing_mode" == active ]]; then
    if BIFROST_SETUP_TEST_EXISTING=true run_creator --confirm >"$tmp/duplicate.out" 2>"$tmp/duplicate.err"; then exit 1; fi
  else
    if BIFROST_SETUP_TEST_ARCHIVED=true run_creator --confirm >"$tmp/archived.out" 2>"$tmp/archived.err"; then exit 1; fi
  fi
  [[ ! -s "$BIFROST_SETUP_OPENSSL_LOG" ]]
  if grep -Fq 'op|item create ' "$BIFROST_SETUP_OP_LOG"; then exit 1; fi
  [[ -z "$(find "$BIFROST_SETUP_TMPDIR" -mindepth 1 -print -quit)" ]]
done

for failure in list template create openssl; do
  : > "$BIFROST_SETUP_OP_LOG"
  : > "$BIFROST_SETUP_OPENSSL_LOG"
  if BIFROST_SETUP_TEST_FAILURE=$failure run_creator --confirm >"$tmp/failure.out" 2>"$tmp/failure.err"; then
    echo "setup-token creator unexpectedly succeeded after $failure failure" >&2
    exit 1
  fi
  if grep -Fq "$BIFROST_SETUP_TEST_RANDOM_HEX" "$tmp/failure.out" "$tmp/failure.err" "$BIFROST_SETUP_OP_LOG" "$BIFROST_SETUP_OPENSSL_LOG"; then
    echo "setup token leaked after $failure failure" >&2
    exit 1
  fi
  [[ -z "$(find "$BIFROST_SETUP_TMPDIR" -mindepth 1 -print -quit)" ]]
done

echo 'Bifrost setup-token creation safety tests passed'
