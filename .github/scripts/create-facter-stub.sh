#!/usr/bin/env bash
# Creates /etc/nixos/facter.json stub for CI builds
# Format: https://github.com/nix-community/nixos-facter
set -euo pipefail

sudo mkdir -p /etc/nixos
sudo tee /etc/nixos/facter.json > /dev/null << 'FACTER_EOF'
{
  "version": 1,
  "hardware": {
    "system": { "uuid": "00000000-0000-0000-0000-000000000000" },
    "cpu": [
      {
        "architecture": "x86_64",
        "vendor_name": "GenuineIntel",
        "features": ["vmx"]
      }
    ],
    "memory": { "total_bytes": 8589934592 },
    "disks": [{ "path": "/dev/sda", "size_bytes": 53687091200 }],
    "network_interfaces": [{ "name": "eth0", "mac": "00:00:00:00:00:00" }],
    "pci": [],
    "scsi": []
  },
  "boot": { "efi_available": true },
  "filesystems": [{ "mountpoint": "/", "device": "/dev/sda1", "fs_type": "ext4" }],
  "virtualisation": "none"
}
FACTER_EOF
echo "facter.json stub created at /etc/nixos/facter.json"
