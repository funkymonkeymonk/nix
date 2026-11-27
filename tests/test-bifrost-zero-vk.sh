#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; printf "Bifrost Zero key-creation harness failed at line %s (status %s)\\n" "$LINENO" "$status" >&2' ERR

[[ "${BIFROST_VK_TASK_VALID:-false}" == true ]] || {
  echo "FAIL: secrets:create-bifrost-zero-vk must require confirm=true and invoke the creator script" >&2
  exit 1
}
[[ -n "${BIFROST_VK_SCRIPT:-}" && -f "$BIFROST_VK_SCRIPT" ]] || {
  echo 'FAIL: Bifrost Zero key creator script is missing' >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/bifrost-zero-vk-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/secure-temp"
if [[ -n "${BIFROST_VK_BASH_BIN:-}" ]]; then
  bash_bin_dir=$(dirname "$BIFROST_VK_BASH_BIN")
  export PATH="$bash_bin_dir:$tmp/bin:$PATH"
else
  export PATH="$tmp/bin:$PATH"
fi
export BIFROST_VK_TMPDIR="$tmp/secure-temp"
export BIFROST_VK_OP_LOG="$tmp/op.log"
export BIFROST_VK_OPENSSL_LOG="$tmp/openssl.log"
export BIFROST_VK_NIX_LOG="$tmp/nix.log"
export BIFROST_VK_CAPTURE="$tmp/generated-key"
export BIFROST_VK_TEMPLATE_SOURCE="$tmp/api-credential-template.json"
export BIFROST_VK_TEST_DEFAULT_VAULT="Opnix"
export BIFROST_VK_TEST_EXISTING="false"
export BIFROST_VK_TEST_EXISTING_ARCHIVED="false"
export BIFROST_VK_TEST_OP_FAILURE=""
export BIFROST_VK_TEST_OPENSSL_FAILURE="false"
export BIFROST_VK_TEST_TEMPLATE_INVALID="false"
export BIFROST_VK_TEST_RANDOM_HEX="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
: > "$BIFROST_VK_OP_LOG"
: > "$BIFROST_VK_OPENSSL_LOG"
: > "$BIFROST_VK_NIX_LOG"

cat > "$BIFROST_VK_TEMPLATE_SOURCE" <<'JSON'
{"title":"","category":"API_CREDENTIAL","fields":[{"id":"credential","type":"CONCEALED","label":"credential","value":""},{"id":"notesPlain","type":"STRING","purpose":"NOTES","label":"notesPlain","value":""}]}
JSON

printf '#!%s\n' "${BIFROST_VK_BASH_BIN:-$(command -v bash)}" > "$tmp/bin/nix"
cat >> "$tmp/bin/nix" <<'MOCK'
printf 'nix|%s\n' "$*" >> "$BIFROST_VK_NIX_LOG"
[[ "$1" == eval && "$2" == --impure && "$3" == --raw && "$4" == '.#nixosConfigurations.zero.config.myConfig.onepassword.defaultVault' ]] || {
  echo "unexpected nix request: $*" >&2
  exit 90
}
printf '%s' "${BIFROST_VK_TEST_DEFAULT_VAULT}"
MOCK

printf '#!%s\n' "${BIFROST_VK_BASH_BIN:-$(command -v bash)}" > "$tmp/bin/openssl"
cat >> "$tmp/bin/openssl" <<'MOCK'
printf 'openssl|%s\n' "$*" >> "$BIFROST_VK_OPENSSL_LOG"
[[ "$*" == 'rand -hex 32' ]] || exit 91
[[ "$BIFROST_VK_TEST_OPENSSL_FAILURE" != true ]] || exit 92
printf '%s\n' "$BIFROST_VK_TEST_RANDOM_HEX"
MOCK

printf '#!%s\n' "${BIFROST_VK_BASH_BIN:-$(command -v bash)}" > "$tmp/bin/op"
cat >> "$tmp/bin/op" <<'MOCK'
printf 'op|%s\n' "$*" >> "$BIFROST_VK_OP_LOG"
[[ "$1" == item ]] || exit 93
case "$2" in
  list)
    [[ "$3" == --include-archive && "$4" == --vault && "$5" == "$BIFROST_VK_TEST_DEFAULT_VAULT" && "$6" == --format && "$7" == json ]] || exit 94
    [[ "$BIFROST_VK_TEST_OP_FAILURE" != list ]] || exit 95
    if [[ "$BIFROST_VK_TEST_EXISTING_ARCHIVED" == true ]]; then
      printf '[{"id":"item-archived","title":"Bifrost Zero API Key","state":"ARCHIVED"}]\n'
    elif [[ "$BIFROST_VK_TEST_EXISTING" == true ]]; then
      printf '[{"id":"item-existing","title":"Bifrost Zero API Key"}]\n'
    else
      printf '[]\n'
    fi
    ;;
  template)
    [[ "$3" == get && "$4" == 'API Credential' ]] || exit 96
    [[ "$BIFROST_VK_TEST_OP_FAILURE" != template ]] || exit 97
    if [[ "$BIFROST_VK_TEST_TEMPLATE_INVALID" == true ]]; then
      printf '{"title":"","category":"LOGIN","fields":[]}\n'
    else
      cat "$BIFROST_VK_TEMPLATE_SOURCE"
    fi
    ;;
  create)
    if [[ "$BIFROST_VK_TEST_OP_FAILURE" == create ]]; then
      printf 'simulated failure for credential sk-bf-%s\n' "$BIFROST_VK_TEST_RANDOM_HEX" >&2
      exit 98
    fi
    vault=''
    template=''
    shift 2
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --vault) vault=$2; shift 2 ;;
        --template) template=$2; shift 2 ;;
        *) echo "unexpected create argument: $1" >&2; exit 99 ;;
      esac
    done
    [[ "$vault" == "$BIFROST_VK_TEST_DEFAULT_VAULT" && -f "$template" ]] || exit 100
    [[ "$(stat -c '%a' "$template")" == 600 ]] || exit 101
    template_dir=$(dirname "$template")
    [[ "$(stat -c '%a' "$template_dir")" == 700 ]] || exit 102
    [[ "$(stat -c '%a' "$template_dir/key")" == 600 ]] || exit 103
    [[ "$(stat -c '%a' "$template_dir/random.hex")" == 600 ]] || exit 104
    [[ "$(stat -c '%a' "$template_dir/api-credential-template.json")" == 600 ]] || exit 105
    jq -e '.title == "Bifrost Zero API Key" and .category == "API_CREDENTIAL" and any(.fields[]; .id == "credential" and .type == "CONCEALED")' "$template" >/dev/null || exit 106
    jq -er '.fields[] | select(.id == "credential") | .value' "$template" > "$BIFROST_VK_CAPTURE"
    secret_for_environment=$(cat "$BIFROST_VK_CAPTURE")
    while IFS= read -r environment_name; do
      environment_value=${!environment_name}
      if [[ "$environment_value" == *"$secret_for_environment"* ]]; then
        printf 'credential was present in environment variable %s\n' "$environment_name" >&2
        exit 107
      fi
    done < <(compgen -e)
    # Model an `op` build that emits a response; the creator must suppress it.
    printf 'created credential: %s\n' "$(cat "$BIFROST_VK_CAPTURE")"
    ;;
  *) exit 105 ;;
esac
MOCK

chmod +x "$tmp/bin/nix" "$tmp/bin/openssl" "$tmp/bin/op"

run_creator() {
  NIX_BIN="$tmp/bin/nix" OPENSSL_BIN="$tmp/bin/openssl" OP_BIN="$tmp/bin/op" \
    "${BIFROST_VK_BASH_BIN:-bash}" "$BIFROST_VK_SCRIPT" "$@"
}

if run_creator >"$tmp/no-confirm.out" 2>"$tmp/no-confirm.err"; then
  echo 'creator unexpectedly ran without explicit confirmation' >&2
  exit 1
fi
[[ ! -s "$BIFROST_VK_OP_LOG" && ! -s "$BIFROST_VK_OPENSSL_LOG" ]]
[[ ! -s "$BIFROST_VK_NIX_LOG" ]]

for task_input in '{}' '{"confirm":false}'; do
  if DEVENV_TASK_INPUT="$task_input" "${BIFROST_VK_BASH_BIN:-bash}" "$BIFROST_VK_TASK_EXEC_SCRIPT" >"$tmp/task-no-confirm.out" 2>"$tmp/task-no-confirm.err"; then
    echo 'Devenv task unexpectedly accepted missing or false confirmation' >&2
    exit 1
  else
    task_status=$?
  fi
  [[ "$task_status" == 64 ]] || {
    echo 'Devenv task did not reject missing or false confirmation with status 64' >&2
    exit 1
  }
  [[ ! -s "$BIFROST_VK_OP_LOG" && ! -s "$BIFROST_VK_OPENSSL_LOG" && ! -s "$BIFROST_VK_NIX_LOG" ]]
done

if run_creator --confirm >"$tmp/create.out" 2>"$tmp/create.err"; then
  :
else
  status=$?
  printf 'Initial creator invocation failed; captured output follows with the test credential redacted:\n' >&2
  sed "s/sk-bf-${BIFROST_VK_TEST_RANDOM_HEX}/[REDACTED]/g" "$tmp/create.out" "$tmp/create.err" >&2
  exit "$status"
fi
created_key=$(cat "$BIFROST_VK_CAPTURE")
[[ "$created_key" =~ ^sk-bf-[0-9a-f]{64}$ ]]
assert_no_key_leak() {
  if grep -Fq "$created_key" "$@"; then
    echo 'generated Bifrost key leaked to command output or logs' >&2
    exit 1
  fi
}
assert_no_item_create() {
  if grep -Fq 'op|item create ' "$BIFROST_VK_OP_LOG"; then
    echo 'creator attempted to create an item when creation was not allowed' >&2
    exit 1
  fi
}
assert_no_success_message() {
  if grep -Fq 'Created 1Password item' "$@"; then
    echo 'creator reported success after an unsuccessful operation' >&2
    exit 1
  fi
}
grep -F 'op|item list --include-archive --vault Opnix --format json' "$BIFROST_VK_OP_LOG" >/dev/null
grep -F 'op|item template get API Credential' "$BIFROST_VK_OP_LOG" >/dev/null
grep -F 'op|item create --vault Opnix --template ' "$BIFROST_VK_OP_LOG" >/dev/null
grep -F 'nix|eval --impure --raw .#nixosConfigurations.zero.config.myConfig.onepassword.defaultVault' "$BIFROST_VK_NIX_LOG" >/dev/null
assert_no_key_leak "$tmp/create.out" "$tmp/create.err" "$BIFROST_VK_OP_LOG" "$BIFROST_VK_OPENSSL_LOG" "$BIFROST_VK_NIX_LOG"
[[ -z "$(find "$BIFROST_VK_TMPDIR" -mindepth 1 -print -quit)" ]]

# The same task uses the configured default vault, not a hard-coded Opnix value.
rm -f "$BIFROST_VK_CAPTURE"
: > "$BIFROST_VK_OP_LOG"
BIFROST_VK_TEST_DEFAULT_VAULT='Vault-Test' run_creator --confirm >"$tmp/alternate-vault.out" 2>"$tmp/alternate-vault.err"
grep -F 'op|item list --include-archive --vault Vault-Test --format json' "$BIFROST_VK_OP_LOG" >/dev/null
grep -F 'op|item create --vault Vault-Test --template ' "$BIFROST_VK_OP_LOG" >/dev/null
[[ -z "$(find "$BIFROST_VK_TMPDIR" -mindepth 1 -print -quit)" ]]

# Existing items are preserved and no new key is generated.
: > "$BIFROST_VK_OPENSSL_LOG"
: > "$BIFROST_VK_OP_LOG"
if BIFROST_VK_TEST_EXISTING=true run_creator --confirm >"$tmp/existing.out" 2>"$tmp/existing.err"; then
  echo 'creator unexpectedly rotated an existing Bifrost key item' >&2
  exit 1
fi
[[ ! -s "$BIFROST_VK_OPENSSL_LOG" ]]
assert_no_item_create
assert_no_success_message "$tmp/existing.out" "$tmp/existing.err"
[[ -z "$(find "$BIFROST_VK_TMPDIR" -mindepth 1 -print -quit)" ]]

# Archived same-title items also count as existing and must prevent creation.
: > "$BIFROST_VK_OPENSSL_LOG"
: > "$BIFROST_VK_OP_LOG"
if BIFROST_VK_TEST_EXISTING_ARCHIVED=true run_creator --confirm >"$tmp/archived.out" 2>"$tmp/archived.err"; then
  echo 'creator unexpectedly created a second item beside an archived Bifrost key' >&2
  exit 1
fi
grep -F 'already exists' "$tmp/archived.err" >/dev/null
[[ ! -s "$BIFROST_VK_OPENSSL_LOG" ]]
assert_no_item_create
assert_no_success_message "$tmp/archived.out" "$tmp/archived.err"
[[ -z "$(find "$BIFROST_VK_TMPDIR" -mindepth 1 -print -quit)" ]]

for failure in list template create; do
  : > "$BIFROST_VK_OP_LOG"
  : > "$BIFROST_VK_OPENSSL_LOG"
  if BIFROST_VK_TEST_OP_FAILURE=$failure run_creator --confirm >"$tmp/op-$failure.out" 2>"$tmp/op-$failure.err"; then
    echo "creator unexpectedly succeeded after op failure: $failure" >&2
    exit 1
  fi
  assert_no_key_leak "$tmp/op-$failure.out" "$tmp/op-$failure.err" "$BIFROST_VK_OP_LOG"
  assert_no_success_message "$tmp/op-$failure.out" "$tmp/op-$failure.err"
  [[ -z "$(find "$BIFROST_VK_TMPDIR" -mindepth 1 -print -quit)" ]]
done

: > "$BIFROST_VK_OP_LOG"
if BIFROST_VK_TEST_TEMPLATE_INVALID=true run_creator --confirm >"$tmp/bad-template.out" 2>"$tmp/bad-template.err"; then
  echo 'creator unexpectedly accepted a template without a concealed credential field' >&2
  exit 1
fi
assert_no_item_create
assert_no_success_message "$tmp/bad-template.out" "$tmp/bad-template.err"
[[ -z "$(find "$BIFROST_VK_TMPDIR" -mindepth 1 -print -quit)" ]]

if BIFROST_VK_TEST_OPENSSL_FAILURE=true run_creator --confirm >"$tmp/openssl-failure.out" 2>"$tmp/openssl-failure.err"; then
  echo 'creator unexpectedly accepted invalid random output' >&2
  exit 1
fi
assert_no_success_message "$tmp/openssl-failure.out" "$tmp/openssl-failure.err"
[[ -z "$(find "$BIFROST_VK_TMPDIR" -mindepth 1 -print -quit)" ]]

if BIFROST_VK_TEST_RANDOM_HEX='not-hex' run_creator --confirm >"$tmp/invalid-random.out" 2>"$tmp/invalid-random.err"; then
  echo 'creator unexpectedly accepted malformed random output' >&2
  exit 1
fi
assert_no_item_create
assert_no_success_message "$tmp/invalid-random.out" "$tmp/invalid-random.err"
[[ -z "$(find "$BIFROST_VK_TMPDIR" -mindepth 1 -print -quit)" ]]

if BIFROST_VK_TEST_DEFAULT_VAULT='' run_creator --confirm >"$tmp/invalid-vault.out" 2>"$tmp/invalid-vault.err"; then
  echo 'creator unexpectedly accepted an empty default vault' >&2
  exit 1
fi
assert_no_success_message "$tmp/invalid-vault.out" "$tmp/invalid-vault.err"
[[ -z "$(find "$BIFROST_VK_TMPDIR" -mindepth 1 -print -quit)" ]]

[[ "${BIFROST_VK_TASK_VALID:-false}" == true ]] || {
  echo 'FAIL: task must require confirm=false by default and invoke the guarded creator' >&2
  exit 1
}

printf 'Bifrost Zero key creation safety tests passed\n'
