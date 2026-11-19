#!/usr/bin/env bash
set -euo pipefail

disko_files=false
install_machine_script=false
vm_smoke_checks=false

if [[ "${1:-}" == "--all" ]]; then
  if (($# != 1)); then
    echo "Usage: $0 [--all] < changed-files.txt" >&2
    exit 64
  fi
  disko_files=true
  install_machine_script=true
  vm_smoke_checks=true
elif (($# > 0)); then
  echo "Usage: $0 [--all] < changed-files.txt" >&2
  exit 64
else
  while IFS= read -r path; do
    case "$path" in
      flake.nix|flake.lock|library/machines/catalog.nix|library/machines/modules.nix|library/machines/flake-parts.nix)
        disko_files=true
        vm_smoke_checks=true
        ;;
      disk-configs/*)
        disko_files=true
        ;;
      machines/*|modules/common/*|modules/nixos/*|modules/roles/*|packages/*|overlays/*|tests/default.nix|tests/vm/*)
        vm_smoke_checks=true
        ;;
      scripts/install-machine.sh)
        install_machine_script=true
        ;;
    esac
  done
fi

printf 'disko-files=%s\ninstall-machine-script=%s\nvm-smoke-checks=%s\n' \
  "$disko_files" "$install_machine_script" "$vm_smoke_checks"
