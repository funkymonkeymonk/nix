#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' '=== SSH-ready NixOS live target ===' '' 'Network addresses (global scope):'
addresses=$(ip -o address show scope global 2>/dev/null || true)
found_address=false
while read -r _ interface family cidr details; do
  [[ -n "${interface:-}" ]] || continue
  [[ "$family" == inet || "$family" == inet6 ]] || continue
  [[ " $details " == *" scope global "* ]] || continue
  case " $details " in
    *' tentative '*|*' dadfailed '*|*' deprecated '*) continue ;;
  esac
  found_address=true
  printf '  %s: %s\n' "${interface%%@*}" "${cidr%%/*}"
done <<< "$addresses"
if [[ "$found_address" == false ]]; then
  printf '%s\n' '  No global addresses are currently available.'
fi

ssh_status=$(systemctl is-active sshd.service 2>/dev/null || true)
printf '\nSSH service (sshd.service): %s\n' "${ssh_status:-unknown}"

public_key=${INSTALLER_READY_PUBLIC_KEY:-/etc/ssh/ssh_host_ed25519_key.pub}
printf 'SSH host-key fingerprint: '
if [[ -r "$public_key" ]]; then
  ssh-keygen -lf "$public_key" || printf '%s\n' 'unavailable'
else
  printf '%s\n' 'unavailable (host public key not found)'
fi

printf '\nAvailable block devices (read-only inventory; no disk changes are made):\n'
lsblk --nodeps --output NAME,SIZE,MODEL,TYPE 2>/dev/null || printf '%s\n' '  Disk inventory is unavailable.'

cat <<'INSTRUCTIONS'

Next steps (run these from your workstation; this ISO does not install locally):
1. Verify the SSH host-key fingerprint over a trusted channel before trusting this target.
2. In the workstation's ignored devenv.local.nix, set machines.<name>.target.host
   to the verified live target address or SSH alias.
3. Run the explicitly named workstation operation:
   devenv tasks run machines:install --input machine=<name>

The workstation owns machine selection, review, credentials, and installation.
This live target only reports readiness; it never partitions, formats, or installs.
INSTRUCTIONS
