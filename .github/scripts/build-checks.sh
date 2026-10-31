#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 {pr|extended|vm-pr|vm-extended}" >&2
}

group="${1:-}"
case "$group" in
  pr)
    selector='.[] | select((startswith("vm-") | not) or . == "vm-role-generator") | select(startswith("overlay-") | not) | select(. != "module-coverage") | select(. != "foundation-packages")'
    ;;
  extended)
    selector='.[] | select(startswith("overlay-") or . == "foundation-packages")'
    ;;
  vm-pr)
    checks=(vm-users vm-ssh vm-packages)
    ;;
  vm-extended)
    checks=(vm-role-foundation vm-role-developer)
    ;;
  *)
    usage
    exit 64
    ;;
esac

nix_bin="${NIX_BIN:-nix}"
max_jobs="${NIX_MAX_JOBS:-2}"
if [[ ! "$max_jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "NIX_MAX_JOBS must be a positive integer (got '$max_jobs')" >&2
  exit 64
fi

current_system=$("$nix_bin" eval --impure --raw --expr 'builtins.currentSystem')
if [[ "$group" == pr || "$group" == extended ]]; then
  check_names=$("$nix_bin" eval --json ".#checks.${current_system}" \
    --apply 'builtins.attrNames' | jq -r "$selector")
  if [[ -n "$check_names" ]]; then
    mapfile -t checks <<< "$check_names"
  else
    checks=()
  fi
fi

installables=()
for check in "${checks[@]}"; do
  installables+=(".#checks.${current_system}.${check}")
done

if ((${#installables[@]} == 0)); then
  echo "No checks selected for group '$group' on $current_system" >&2
  exit 1
fi

echo "Building ${#installables[@]} '${group}' checks on ${current_system} (max-jobs: ${max_jobs})"
"$nix_bin" build --no-link --max-jobs "$max_jobs" "${installables[@]}"
