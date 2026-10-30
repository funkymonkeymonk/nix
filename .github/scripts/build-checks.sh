#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <non-vm|vm>" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
suite=$1
nix_bin=${NIX_BIN:-nix}
current_system=$("$nix_bin" eval --impure --raw --expr 'builtins.currentSystem')

case "$suite" in
  non-vm)
    check_names=$("$nix_bin" eval --json ".#checks.${current_system}" --apply 'builtins.attrNames' \
      | jq -r '.[] | select(startswith("vm-") | not)')
    mapfile -t checks <<<"$check_names"
    nix_args=(build --no-link --print-build-logs)
    ;;
  vm)
    checks=(
      vm-users
      vm-ssh
      vm-packages
      vm-role-foundation
      vm-role-developer
    )
    nix_args=(build --no-link --print-build-logs --max-jobs 2)
    ;;
  *) usage ;;
esac

((${#checks[@]} > 0)) || {
  echo "No checks selected for suite '$suite'" >&2
  exit 1
}

installables=()
for check in "${checks[@]}"; do
  installables+=(".#checks.${current_system}.${check}")
done

printf 'Building %d %s checks in one Nix invocation\n' "${#checks[@]}" "$suite"
"$nix_bin" "${nix_args[@]}" "${installables[@]}"
