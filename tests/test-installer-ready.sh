#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper_script=${INSTALLER_READY_SCRIPT:-"$repo_root/packages/installer-ready/installer-ready.sh"}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
export INSTALLER_READY_TEST_LOG="$tmp/commands.log"
export PATH="$tmp/bin:$PATH"
export INSTALLER_READY_PUBLIC_KEY="$tmp/ssh_host_ed25519_key.pub"
export UNRELATED_ENVIRONMENT_SECRET=must-not-be-printed
: > "$INSTALLER_READY_TEST_LOG"
: > "$INSTALLER_READY_PUBLIC_KEY"

printf '#!%s\n' "$BASH" > "$tmp/bin/ip"
cat >> "$tmp/bin/ip" <<'MOCK'
[[ "$*" == "-o address show scope global" ]] || exit 91
cat <<'OUTPUT'
2: enp1s0 inet 192.0.2.25/24 brd 192.0.2.255 scope global dynamic enp1s0
2: enp1s0 inet6 2001:db8::25/64 scope global dynamic mngtmpaddr
2: enp1s0 inet 169.254.8.4/16 scope link enp1s0
3: wlan0 inet6 2001:db8::99/64 scope global tentative
OUTPUT
MOCK

printf '#!%s\n' "$BASH" > "$tmp/bin/systemctl"
cat >> "$tmp/bin/systemctl" <<'MOCK'
[[ "$*" == "is-active sshd.service" ]] || exit 92
printf 'active\n'
MOCK

printf '#!%s\n' "$BASH" > "$tmp/bin/ssh-keygen"
cat >> "$tmp/bin/ssh-keygen" <<'MOCK'
[[ "$*" == "-lf $INSTALLER_READY_PUBLIC_KEY" ]] || exit 93
printf '256 SHA256:mock-host-fingerprint root@installer (ED25519)\n'
MOCK

printf '#!%s\n' "$BASH" > "$tmp/bin/lsblk"
cat >> "$tmp/bin/lsblk" <<'MOCK'
[[ "$*" == "--nodeps --output NAME,SIZE,MODEL,TYPE" ]] || exit 94
printf 'sda 32G QEMU_HARDDISK disk\n'
MOCK

printf '#!%s\n' "$BASH" > "$tmp/bin/forbidden-operation"
cat >> "$tmp/bin/forbidden-operation" <<'MOCK'
printf '%s\n' "${0##*/} $*" >> "$INSTALLER_READY_TEST_LOG"
exit 95
MOCK
for command in \
  cfdisk dd disko fdisk mkfs.ext4 mkfs.vfat mount nix nixos-anywhere \
  nixos-install nixos-rebuild op parted secretspec wipefs; do
  ln -s "$tmp/bin/forbidden-operation" "$tmp/bin/$command"
done
chmod +x "$tmp/bin"/*

output=$(bash "$helper_script")
printf '%s\n' "$output"

assert_contains() {
  local description=$1
  local expected=$2
  if ! grep -Fq -- "$expected" <<< "$output"; then
    printf 'FAIL: %s (missing %q)\n' "$description" "$expected" >&2
    exit 1
  fi
}

assert_not_contains() {
  local description=$1
  local unexpected=$2
  if grep -Fq -- "$unexpected" <<< "$output"; then
    printf 'FAIL: %s (unexpected %q)\n' "$description" "$unexpected" >&2
    exit 1
  fi
}

assert_contains 'global IPv4 address is reported' 'enp1s0: 192.0.2.25'
assert_contains 'global IPv6 address is reported' 'enp1s0: 2001:db8::25'
assert_not_contains 'link-local address is excluded' '169.254.8.4'
assert_not_contains 'tentative address is excluded' '2001:db8::99'
assert_contains 'SSH service status is reported' 'SSH service (sshd.service): active'
assert_contains 'public SSH host-key fingerprint is reported' 'SHA256:mock-host-fingerprint'
assert_contains 'read-only disk inventory is reported' 'sda 32G QEMU_HARDDISK disk'
assert_contains 'operator is told to verify host key before trust' 'Verify the SSH host-key fingerprint'
assert_contains 'operator is directed to ignored local host override' 'devenv.local.nix'
assert_contains 'operator is directed to set target host' 'machines.<name>.target.host'
assert_contains 'operator is directed to named workstation install task' 'devenv tasks run machines:install --input machine=<name>'
assert_not_contains 'unrelated environment values are not printed' 'must-not-be-printed'
[[ ! -s "$INSTALLER_READY_TEST_LOG" ]] || {
  printf 'FAIL: helper attempted a disk write, install, or secret lookup:\n' >&2
  cat "$INSTALLER_READY_TEST_LOG" >&2
  exit 1
}

printf 'installer-ready helper safety tests passed\n'
