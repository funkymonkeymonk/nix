#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ $# -eq 1 && "$1" == --confirm ]] || fail 'pass --confirm to create the 1Password item'

nix_bin=${NIX_BIN:-nix}
op_bin=${OP_BIN:-op}
openssl_bin=${OPENSSL_BIN:-openssl}
item_title='Bifrost Zero API Key'

command -v "$nix_bin" >/dev/null 2>&1 || fail 'Nix CLI is required'
command -v "$op_bin" >/dev/null 2>&1 || fail '1Password CLI (op) is required'
command -v "$openssl_bin" >/dev/null 2>&1 || fail 'OpenSSL is required'

default_vault=$("$nix_bin" eval --impure --raw '.#nixosConfigurations.zero.config.myConfig.onepassword.defaultVault') || fail 'unable to resolve Zero defaultVault'
[[ -n "$default_vault" && "$default_vault" != *$'\n'* && "$default_vault" != *$'\r'* ]] || fail 'Zero defaultVault is invalid'

items_json=$("$op_bin" item list --include-archive --vault "$default_vault" --format json) || fail "unable to list items in the default vault $default_vault"
jq -e 'type == "array"' <<<"$items_json" >/dev/null || fail '1Password returned an invalid item list'
if jq -e --arg title "$item_title" 'any(.[]; .title == $title)' <<<"$items_json" >/dev/null; then
  fail "item '$item_title' already exists in $default_vault; refusing to overwrite or rotate it"
fi

tmp_root=${BIFROST_VK_TMPDIR:-/tmp/opencode}
mkdir -p -- "$tmp_root" || fail 'unable to create the temporary-file parent directory'
umask 077
tmpdir=$(mktemp -d "$tmp_root/bifrost-zero-vk.XXXXXX") || fail 'unable to create a private temporary directory'

cleanup() {
  if [[ -n "${tmpdir:-}" && -d "$tmpdir" ]]; then
    rm -f -- "$tmpdir/random.hex" "$tmpdir/key" "$tmpdir/api-credential-template.json" "$tmpdir/item.json"
    rmdir "$tmpdir" 2>/dev/null || true
  fi
  return 0
}
trap cleanup EXIT
chmod 0700 "$tmpdir"

random_file="$tmpdir/random.hex"
key_file="$tmpdir/key"
source_template="$tmpdir/api-credential-template.json"
item_template="$tmpdir/item.json"

if ! "$op_bin" item template get 'API Credential' >"$source_template"; then
  fail 'unable to retrieve the 1Password API Credential template'
fi
chmod 0600 "$source_template"
jq -e '
  .category == "API_CREDENTIAL"
  and (.fields | type == "array")
  and ([.fields[] | select(.id == "credential" and .type == "CONCEALED")] | length == 1)
' "$source_template" >/dev/null || fail 'API Credential template has no concealed credential field'

if ! "$openssl_bin" rand -hex 32 | tr -d '\n' >"$random_file"; then
  fail 'OpenSSL failed to generate a random virtual-key value'
fi
chmod 0600 "$random_file"
grep -Eq '^[0-9a-f]{64}$' "$random_file" || fail 'OpenSSL returned an invalid random value'
{
  printf 'sk-bf-'
  cat "$random_file"
} >"$key_file"
chmod 0600 "$key_file"

if ! jq --arg title "$item_title" --rawfile credential "$key_file" '
  .title = $title
  | .fields |= map(if .id == "credential" then .value = $credential else . end)
' "$source_template" >"$item_template"; then
  fail 'unable to prepare the API Credential template'
fi
chmod 0600 "$item_template"
jq -e --arg title "$item_title" --rawfile credential "$key_file" '
  .title == $title
  and .category == "API_CREDENTIAL"
  and any(.fields[]; .id == "credential" and .type == "CONCEALED" and .value == $credential)
' "$item_template" >/dev/null || fail 'prepared API Credential template failed validation'

if ! "$op_bin" item create --vault "$default_vault" --template "$item_template" >/dev/null 2>&1; then
  fail "1Password failed to create '$item_title' in $default_vault"
fi

printf 'Created 1Password item "%s" in vault "%s" (credential field); key value was not displayed.\n' "$item_title" "$default_vault"
