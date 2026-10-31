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

compute_drv_hash() {
  local config="$1" type="$2" drv_path drv_hash
  if [[ "$type" == darwin ]]; then
    drv_path=$(nix eval --raw ".#darwinConfigurations.${config}.system.drvPath")
  else
    drv_path=$(nix eval --impure --raw \
      ".#nixosConfigurations.${config}.config.system.build.toplevel.drvPath")
  fi
  if [[ -z "$drv_path" ]]; then
    echo "Could not evaluate ${type} configuration '${config}'" >&2
    return 1
  fi
  drv_hash=$(nix-store -q --hash "$drv_path")
  if [[ -z "$drv_hash" ]]; then
    echo "Could not compute derivation hash for ${type} configuration '${config}'" >&2
    return 1
  fi
  printf '%s\n' "$drv_hash"
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
  new_hash=$(compute_drv_hash "$config" darwin)
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
  new_hash=$(compute_drv_hash "$config" nixos)
  if [[ "$old_hash" != "$new_hash" ]]; then
    echo "NixOS config '${config}' changed"
    if [[ "$config" =~ -arm(-|$) ]]; then
      nixos_arm_changed+=("$config")
    else
      nixos_changed+=("$config")
    fi
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
