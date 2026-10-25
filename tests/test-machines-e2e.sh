#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source "$repo_root/tests/lib/machines-e2e-status.sh"

fail() {
  echo "machines e2e: $*" >&2
  exit 1
}

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "machines e2e requires an x86_64-linux host" >&2
  exit 77
}

for command in jq nix ssh ssh-keygen ssh-keyscan python3; do
  command -v "$command" >/dev/null || fail "required command is missing: $command"
done

tmp_root=${TMPDIR:-/tmp}
tmp_root=$(realpath -m -- "$tmp_root")
case "$tmp_root/" in
  "$repo_root/"*|/nix/store/*)
    fail "TMPDIR must be outside the repository and Nix store: $tmp_root"
    ;;
esac

tmp=$(mktemp -d "$tmp_root/machines-e2e.XXXXXXXX")
chmod 700 "$tmp"
vm_pid=
cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [[ -n "$vm_pid" ]]; then
    kill "$vm_pid" 2>/dev/null || true
    wait "$vm_pid" 2>/dev/null || true
  fi
  rm -rf -- "$tmp"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

ssh-keygen -q -t ed25519 -N '' -C machines-e2e -f "$tmp/id_ed25519"
public_key=$(<"$tmp/id_ed25519.pub")
[[ "$public_key" == ssh-ed25519\ * ]] || fail "ssh-keygen did not produce an Ed25519 public key"

# Ask the kernel for an unused loopback port; never accept a caller-selected
# port that could point at a reused or non-loopback service.
ssh_port=$(python3 - <<'PY'
import socket
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)
[[ "$ssh_port" =~ ^[0-9]+$ ]] && ((ssh_port > 0 && ssh_port <= 65535)) || fail "could not select a safe loopback port"
if ! python3 - "$ssh_port" <<'PY'
import socket
import sys

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    try:
        sock.bind(("127.0.0.1", int(sys.argv[1])))
    except OSError as error:
        raise SystemExit(f"SSH port is already occupied on loopback: {error}")
PY
then
  fail "refusing to start QEMU on an occupied loopback port: $ssh_port"
fi

project="$tmp/project"
mkdir -m 700 "$project"
cp -- "$repo_root/devenv.yaml" "$repo_root/devenv.lock" "$project/"
python3 - "$project/devenv.nix" "$ssh_port" "$tmp/id_ed25519" "$tmp/known_hosts" "$public_key" <<'PY'
import json
import sys
from pathlib import Path

project_file, port, identity_file, known_hosts_file, public_key = sys.argv[1:]
quote = json.dumps
project_text = f'''{{ ... }}: {{
  machines.integration = {{
    system = "x86_64-linux";
    hardware.facter = null;
    target.host = "root@127.0.0.1:{port}";
    target.sshOpts = [
      "-i"
      {quote(identity_file)}
      "-o"
      "IdentitiesOnly=yes"
      "-o"
      "BatchMode=yes"
      "-o"
      "StrictHostKeyChecking=yes"
      "-o"
      {quote("UserKnownHostsFile=" + known_hosts_file)}
      "-o"
      "ConnectTimeout=5"
    ];
    nixos = {{ lib, ... }}: {{
      system.stateVersion = "25.05";
      fileSystems."/" = {{
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      }};
      boot.loader.grub.devices = lib.mkForce [ "nodev" ];
      networking.useDHCP = true;
      services.openssh.enable = true;
      services.openssh.settings = {{
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        PubkeyAuthentication = true;
      }};
      networking.firewall.allowedTCPPorts = [ 22 ];
      users.users.root.openssh.authorizedKeys.keys = [ {quote(public_key)} ];
      environment.etc."machines-e2e-marker".text = "deployed-by-machines-e2e\\n";
    }};
  }};
}}
'''
Path(project_file).write_text(project_text)
PY

cli_path=$(nix build "$repo_root#devenv" --no-link --print-out-paths)
cli="$cli_path/bin/devenv"
[[ -x "$cli" ]] || fail "the root flake's pinned devenv CLI was not built"

build_json=$(
  cd "$project"
  "$cli" build machines.integration.build.nixos
)
printf '%s\n' "$build_json"
deployment_system=$(jq -r '."machines.integration.build.nixos" // empty' <<<"$build_json")
[[ "$deployment_system" =~ ^/nix/store/[a-z0-9]{32}-nixos-system-[^/]+$ ]] || fail "devenv returned an invalid NixOS system output"

# Only the intentionally public half of the disposable keypair and the
# synthetic NixOS system output cross the impure VM-build boundary. The private
# key remains under $tmp and is never an input to a Nix build or copied into
# the project/store. Pre-seeding the system closure gives the local guest store
# enough space before the Machines controller applies it.
export MACHINES_E2E_PUBLIC_KEY="$public_key"
export MACHINES_E2E_SSH_PORT="$ssh_port"
export MACHINES_E2E_DEPLOYMENT_SYSTEM="$deployment_system"
vm_path=$(nix build "$repo_root#machines-e2e-vm" --impure --no-link --print-out-paths)
[[ -x "$vm_path/bin/run-nixos-vm" ]] || fail "machines-e2e-vm did not expose system.build.vm"

mkdir -m 700 "$tmp/vm-tmp"
NIX_DISK_IMAGE="$tmp/target.qcow2" TMPDIR="$tmp/vm-tmp" USE_TMPDIR=1 \
  "$vm_path/bin/run-nixos-vm" -nographic >"$tmp/qemu.log" 2>&1 &
vm_pid=$!

known_hosts="$tmp/known_hosts"
for _ in $(seq 1 120); do
  if ! kill -0 "$vm_pid" 2>/dev/null; then
    cat "$tmp/qemu.log" >&2
    fail "QEMU exited before its loopback SSH port became available"
  fi
  keyscan=$(ssh-keyscan -T 2 -p "$ssh_port" -t ed25519 127.0.0.1 2>/dev/null || true)
  if [[ -n "$keyscan" ]]; then
    printf '%s\n' "$keyscan" >"$known_hosts"
    chmod 600 "$known_hosts"
    break
  fi
  sleep 1
done
[[ -s "$known_hosts" ]] || {
  cat "$tmp/qemu.log" >&2
  fail "timed out waiting for SSH on 127.0.0.1:$ssh_port"
}

ssh_options=(
  -i "$tmp/id_ed25519"
  -o IdentitiesOnly=yes
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$known_hosts"
  -o ConnectTimeout=5
  -p "$ssh_port"
)
if ! ssh "${ssh_options[@]}" root@127.0.0.1 'test -d /run/current-system' 2>"$tmp/ssh-readiness.log"; then
  cat "$tmp/ssh-readiness.log" >&2
  cat "$tmp/qemu.log" >&2
  fail "the disposable target did not accept its ephemeral key over strict SSH"
fi
# A standalone system.build.vm does not create the NixOS system profile that
# Machines uses to observe the currently running generation. Seed that profile
# only inside this disposable guest before planning.
ssh "${ssh_options[@]}" root@127.0.0.1 \
  'nix-env --profile /nix/var/nix/profiles/system --set "$(readlink -f /run/current-system)"'

(
  cd "$project"
  "$cli" machines info
  "$cli" machines plan integration
)

mapfile -t plans < <(find "$project/.devenv/machine-plans" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
[[ ${#plans[@]} -eq 1 ]] || fail "expected one saved integration plan, found ${#plans[@]}"
plan_id=${plans[0]}
[[ "$plan_id" =~ ^[A-Za-z0-9._-]+$ ]] || fail "devenv returned an unsafe plan identifier"
collect_target_diagnostics() {
  local status_json=${1:-}
  [[ -z "$status_json" ]] || printf '%s\n' "$status_json" >&2
  local unit
  unit=$(jq -r '.integration.unit // empty' <<<"${status_json:-{} }" 2>/dev/null || true)
  if [[ "$unit" =~ ^devenv-machine-deployment-[A-Za-z0-9-]+\.service$ ]]; then
    ssh "${ssh_options[@]}" root@127.0.0.1 \
      "systemctl status --no-pager '$unit'; journalctl -b -u '$unit' --no-pager -o cat; journalctl -b -p err --no-pager -n 80" >&2 || true
  fi
  ssh "-vvv" "${ssh_options[@]}" root@127.0.0.1 true >"$tmp/ssh-banner-trace.log" 2>&1 || true
  cat "$tmp/ssh-banner-trace.log" >&2
  ssh "${ssh_options[@]}" root@127.0.0.1 \
    'systemctl --failed --no-pager; journalctl -b --no-pager -n 40' >&2 || true
  tail -n 120 "$tmp/qemu.log" >&2
}
if ! (
  cd "$project"
  "$cli" machines apply "$plan_id"
); then
  echo "machines e2e: reconciling target status after apply lost observation" >&2
  apply_confirmed=false
  confirmation_requested=false
  confirmation_transaction_id=
  status_error="$tmp/status-error.log"
  for _ in $(seq 1 180); do
    status_json=$(
      cd "$project"
      "$cli" machines status integration 2>"$status_error"
    ) || status_json=
    if [[ -n "$status_json" ]]; then
      phase=$(jq -r '.integration.phase // empty' <<<"$status_json")
      if machines_e2e_status_is_success "$phase"; then
        echo "machines e2e: target confirms plan $plan_id succeeded" >&2
        apply_confirmed=true
        break
      fi
      case "$phase" in
        awaiting-confirmation)
          transaction_id=$(jq -r '.integration.id // empty' <<<"$status_json")
          [[ "$transaction_id" =~ ^[A-Za-z0-9-]{1,100}$ ]] || fail "target returned an unsafe transaction identifier"
          if [[ "$confirmation_requested" == true ]]; then
            if [[ "$transaction_id" != "$confirmation_transaction_id" ]]; then
              collect_target_diagnostics "$status_json"
              fail "target transaction changed after confirmation was requested"
            fi
          else
            ssh "${ssh_options[@]}" root@127.0.0.1 \
              'test "$(cat /etc/machines-e2e-marker)" = "deployed-by-machines-e2e"'
            ssh "${ssh_options[@]}" root@127.0.0.1 \
              "/nix/var/nix/gcroots/devenv-machines/executor/bin/devenv-machine-deploy confirm '$transaction_id'"
            confirmation_transaction_id=$transaction_id
            confirmation_requested=true
            echo "machines e2e: target marker passed; transaction $transaction_id confirmed; polling for terminal success" >&2
          fi
          ;;
        failed|rolled-back|rollback-failed)
          collect_target_diagnostics "$status_json"
          fail "Machines apply reached terminal target phase $phase"
          ;;
      esac
    fi
    sleep 2
  done
  if [[ "$apply_confirmed" != true ]]; then
    status_json=$(
      cd "$project"
      "$cli" machines status integration 2>/dev/null
    ) || status_json=
    phase=$(jq -r '.integration.phase // empty' <<<"${status_json:-}")
    if machines_e2e_status_is_success "$phase"; then
      echo "machines e2e: target confirms plan $plan_id succeeded" >&2
      apply_confirmed=true
    fi
  fi
  if [[ "$apply_confirmed" != true ]]; then
    [[ ! -s "$status_error" ]] || cat "$status_error" >&2
    collect_target_diagnostics "${status_json:-}"
    fail "Machines apply did not reach a confirmed successful target phase for plan $plan_id"
  fi
fi

ssh "${ssh_options[@]}" root@127.0.0.1 \
  'test "$(cat /etc/machines-e2e-marker)" = "deployed-by-machines-e2e"'
echo "machines e2e: plan $plan_id applied; marker verified over strict SSH"
