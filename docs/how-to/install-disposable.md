---
title: "Install NixOS with Disposable Infrastructure"
description: "Step-by-step guide for installing NixOS using the disposable infrastructure approach"
type: how-to
audience: both
automation-ready: false
last-reviewed: 2026-04-06
---

# Install NixOS with Disposable Infrastructure

This guide shows you how to install NixOS using the disposable infrastructure approach with automatic hardware detection.

## Prerequisites

- Target machine booted with NixOS installer
- SSH enabled on target (run `systemctl start sshd` and `passwd`)
- `gum` installed in your environment (provided by devenv)
- Network connectivity between deployment machine and target

## Installation Methods

### Method 1: Interactive TUI (Recommended)

The installer uses a beautiful ncurses-style TUI powered by [gum](https://github.com/charmbracelet/gum) from Charm.

```bash
# Boot target machine from NixOS USB installer
# Set password: passwd
# Check IP: ip addr

# From your deployment machine:
./scripts/install-machine.sh
```

The interactive installer will guide you through:

1. **SSH Connection** - Test connection to target machine
2. **Machine Type** - Choose desktop or server
3. **Hostname** - Auto-generated based on existing machines
4. **Disk Selection** - Interactive list of physical disks
5. **Auto-Updates** - Configure automatic updates from your flake
6. **Confirmation** - Final review before installation

That's it! The script will:
- Partition and format the selected disk
- Auto-detect all hardware
- Install NixOS with the chosen configuration
- Set up SSH with auto-generated keys
- Configure auto-updates (if enabled)

### Method 2: Manual/Non-Interactive

For automation or scripting, use nixos-anywhere directly:

```bash
# Install a type-server
nix run github:nix-community/nixos-anywhere -- \
  --flake .#type-server \
  --target-host root@192.168.1.100 \
  --disko-mode disformat

# Install a type-desktop
nix run github:nix-community/nixos-anywhere -- \
  --flake .#type-desktop \
  --target-host root@192.168.1.100 \
  --disko-mode disformat
```

## Post-Install Steps

### For Takeout Container Machines (type-desktop, type-server)

These are ready to use immediately! The configuration is pure and self-contained:

```bash
# SSH into new machine
ssh monkey@<hostname>  # Hostname assigned via DHCP

# System is already fully configured and auto-updating from GitHub
```

### For Artisanal Machines (bootstrap → named host)

If you used bootstrap to create an artisanal machine:

```bash
# SSH into new machine
ssh root@192.168.1.100

# Copy the generated facter.json
nixos-facter > /etc/nixos/facter.json

# Create a proper target in your flake (see add-machine.md)
nixos-rebuild switch --flake github:youruser/nix#<hostname>
```

## Interactive Features

The TUI installer provides:

**SSH Connection Testing**
- Automatically tests SSH connectivity before proceeding
- Clear error messages with troubleshooting steps
- Retry option if connection fails

**Smart Hostname Generation**
- Automatically suggests next hostname based on existing machines
- Shows existing hosts for reference
- Validates hostname format

**Physical Disk Discovery**
- Lists all physical disks from target machine
- Shows size, type (SSD/HDD), and model
- Warns before destructive operations

**Auto-Update Configuration**
- Toggle automatic updates on/off
- Select update time (defaults to 04:00)
- Defaults to `github:funkymonkeymonk/nix`

## Migration Checklist

### Before Migration
- [ ] Backup data from target machine
- [ ] Note the target machine's IP address

### During Migration  
- [ ] Boot NixOS USB on target
- [ ] Start SSH: `systemctl start sshd`
- [ ] Set password: `passwd`
- [ ] Run `./scripts/install-machine.sh` and follow TUI prompts
- [ ] Wait for completion (5-10 minutes)
- [ ] SSH into new system: `ssh root@<hostname>`

### After Migration
- [ ] Restore data from backup
- [ ] Test all hardware (graphics, audio, network)
- [ ] Update DNS/known_hosts (SSH key changed)
- [ ] Delete old artisanal config (optional)

## Troubleshooting

### "Device not found"

Check the disk device name:
```bash
# On target machine
lsblk
```

### SSH connection fails

Ensure target has SSH enabled in installer:
```bash
# On target
systemctl start sshd
passwd  # Set password
```

### Hardware not detected

nixos-facter requires kexec or installer image. If on existing Linux:
```bash
# May need to boot NixOS installer USB instead
```

### Installation fails mid-way

```bash
# Check what would be installed (dry run)
nix run github:nix-community/nixos-anywhere -- \
  --flake .#type-desktop \
  --target-host root@192.168.1.100 \
  --dry-run

# Debug disk detection
lsblk -f  # On target machine

# Test hardware detection
nix run github:nix-community/nixos-facter -- -o facter.json
```

---

## Related Documents

- [Disposable Infrastructure](../explanation/disposable-infrastructure.md) - Philosophy and design
- [Install Disposable Quick Reference](install-disposable-quick-reference.md) - Quick reference
- [Add a New Machine](add-machine.md) - Adding machines to flake
- [nixos-anywhere docs](https://github.com/nix-community/nixos-anywhere/tree/main/docs)
- [disko examples](https://github.com/nix-community/disko/tree/master/example)
