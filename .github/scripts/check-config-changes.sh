#!/usr/bin/env bash
set -euo pipefail

cache_dir="${DRV_CACHE_DIR:-.drv-cache}"
staging_dir="${DRV_CACHE_STAGING:-${cache_dir}-staging}"
darwin_configs="${DARWIN_CONFIGS:-[]}"
nixos_configs="${NIXOS_CONFIGS:-[]}"
output_file="${GITHUB_OUTPUT:-/dev/stdout}"

validate_config_list() {
  local label="$1" json="$2"
  if ! jq -e 'type == "array" and all(.[]; type == "string" and test("^[A-Za-z0-9_-]+$"))' \
    <<< "$json" >/dev/null; then
    echo "Invalid ${label} configuration list" >&2
    return 1
  fi
}

validate_config_list Darwin "$darwin_configs"
validate_config_list NixOS "$nixos_configs"

darwin_drv_paths=$(nix eval --json .#darwinConfigurations \
  --apply 'x: builtins.mapAttrs (_: config: config.system.drvPath) x')
nixos_drv_paths=$(nix eval --impure --json .#nixosConfigurations \
  --apply 'x: builtins.mapAttrs (name: config: if builtins.match ".*-arm(-|$)" name != null then null else config.config.system.build.toplevel.drvPath) x')

derivation_path() {
  local config="$1" paths="$2" type="$3" drv_path
  drv_path=$(jq -er --arg config "$config" \
    '.[$config] | select(type == "string" and length > 0)' <<< "$paths") || {
    echo "Could not evaluate ${type} configuration '${config}'" >&2
    return 1
  }
  printf '%s\n' "$drv_path"
}

json_array() {
  if (($# == 0)); then
    printf '[]'
  else
    printf '%s\n' "$@" | jq -R . | jq -cs .
  fi
}

mkdir -p "$(dirname "$staging_dir")"
rm -rf "$staging_dir"
mkdir -p "$staging_dir"
darwin_changed=()
nixos_changed=()
nixos_arm_changed=()

while IFS= read -r config; do
  old_hash=""
  if [[ -f "$cache_dir/darwin-${config}.hash" ]]; then
    old_hash=$(<"$cache_dir/darwin-${config}.hash")
  fi
  new_hash=$(derivation_path "$config" "$darwin_drv_paths" darwin)
  if [[ "$old_hash" != "$new_hash" ]]; then
    echo "Darwin config '${config}' changed"
    darwin_changed+=("$config")
  else
    echo "Darwin config '${config}' unchanged"
  fi
  printf '%s\n' "$new_hash" > "$staging_dir/darwin-${config}.hash"
done < <(jq -r '.[]' <<< "$darwin_configs")

while IFS= read -r config; do
  old_hash=""
  if [[ -f "$cache_dir/nixos-${config}.hash" ]]; then
    old_hash=$(<"$cache_dir/nixos-${config}.hash")
  fi
  if [[ "$config" =~ -arm(-|$) ]]; then
    echo "NixOS ARM config '${config}' will be evaluated by its native build runner"
    nixos_arm_changed+=("$config")
    continue
  fi
  new_hash=$(derivation_path "$config" "$nixos_drv_paths" nixos)
  if [[ "$old_hash" != "$new_hash" ]]; then
    echo "NixOS config '${config}' changed"
    nixos_changed+=("$config")
  else
    echo "NixOS config '${config}' unchanged"
  fi
  printf '%s\n' "$new_hash" > "$staging_dir/nixos-${config}.hash"
done < <(jq -r '.[]' <<< "$nixos_configs")

printf '%s\n' "$darwin_configs" > "$staging_dir/darwin-configs"
printf '%s\n' "$nixos_configs" > "$staging_dir/nixos-configs"

# Replace the cache only after every current config has a valid hash. A failed
# evaluation therefore leaves the last usable cache intact.
backup_dir="${cache_dir}.backup.$$"
rm -rf "$backup_dir"
if [[ -e "$cache_dir" ]]; then
  mv "$cache_dir" "$backup_dir"
fi
if mv "$staging_dir" "$cache_dir"; then
  rm -rf "$backup_dir"
else
  if [[ -e "$backup_dir" ]]; then
    mv "$backup_dir" "$cache_dir"
  fi
  exit 1
fi

{
  printf 'darwin-changed=%s\n' "$(json_array "${darwin_changed[@]}")"
  printf 'nixos-changed=%s\n' "$(json_array "${nixos_changed[@]}")"
  printf 'nixos-arm-changed=%s\n' "$(json_array "${nixos_arm_changed[@]}")"
  printf 'darwin-configs=%s\n' "$darwin_configs"
  printf 'nixos-configs=%s\n' "$nixos_configs"
} >> "$output_file"
