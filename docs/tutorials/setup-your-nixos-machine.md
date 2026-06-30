---
title: "Set Up Your NixOS Machine"
description: "Step-by-step walkthrough for booting from USB and installing NixOS with this flake"
type: tutorial
audience: both
last-reviewed: 2026-06-30
---

# Set Up Your NixOS Machine

This tutorial walks through installing NixOS on a bare-metal or virtual machine. By the end, you will have a running system managed by this flake with automatic hardware detection and disk partitioning.

## Prerequisites

- A machine (physical or VM) targeted for NixOS
- A USB drive at least 4 GB
- A workstation (Mac or Linux) with Nix installed to create the installer image
- About 45 minutes total

## Step 1: Create the Installer USB

From a machine with Nix (macOS or Linux), build and write the custom installer image:

```bash
# Build the ISO (takes a few minutes the first time)
nix build github:funkymonkeymonk/nix#packages.x86_64-linux.iso --impure

# Write to USB - replace sdX with your actual device
sudo dd if=./result/iso-image.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

You can also use the installer from NixOS Live session or macOS with Balena Etcher.

## Step 2: Boot the Installer USB

1. Insert the USB drive into the target machine
2. Boot from the USB (may require pressing F12, Esc, or Del during POST)
3. The installer TUI starts automatically on TTY1
4. Press Alt+F2 for a shell if you need to troubleshoot before proceeding

## Step 3: Choose Your Configuration

The installer TUI shows available targets and machine types.

For headless servers choose `type-server` — it includes MicroVM support, Tailscale, and auto-upgrades, and requires no hardware-configuration.nix because nixos-facter detects the hardware automatically. Notice that a takeout container hostname comes from DHCP.

If you added a custom target into `flake.nix` beforehand, its name appears in the installer list too.

## Step 4: Select the Disk

The installer scans physical disks with `lsblk` and displays them in a table. It warns that all data on the selected disk will be destroyed.

Notice that auto-partitioning uses disko — you do not need to run `cfdisk` or `parted` manually.

## Step 5: Confirm and Install

The installer shows an installation summary before proceeding. If everything looks correct, confirm to begin installation.

This step:
1. Partitions the disk with disko (EFI + root ext4)
2. Formats ext4 on the root partition
3. Mounts partitions under `/mnt`
4. Generates hardware configuration using nixos-facter
5. Runs `nixos-install --flake github:funkymonkeymonk/nix#<target>`

If the target machine has network access, the installer uses the remote flake from GitHub. Otherwise it falls back to the copy bundled on the ISO.

## Step 6: Boot into Your System

Remove the USB drive and reboot. The system boots into the installed NixOS configuration with systemd-boot.

### Verify SSH Access

```bash
# From another machine on the same network
ssh admin@<hostname-or-ip>
```

The `type-server` target includes SSH key authentication only (no password) with agent forwarding for 1Password.

## Step 7: Run Post-Installation Checks

SSH into the machine or use the TTY and verify:

```bash
# Check system configuration
nixos-rebuild list-generations

# Verify flakes are enabled
nix flake show /etc/nixos 2>/dev/null || echo "No local flake (remote install)"

# Test that auto-upgrade is configured
cat /etc/nixos/configuration.nix | grep -A5 autoUpgrade
```

On `type-server` and `type-desktop` the system checks for upgrades at 04:00 daily.

## Step 8 (Heirloom Only): Create Your Target

If you installed a custom configuration rather than a takeout container, make sure you have a target directory wired into `flake.nix`:

```bash
mkdir -p targets/my-nixos
```

Copy hardware config from the running system:

```bash
ssh admin@my-nixos "cat /etc/nixos/hardware-configuration.nix" \
  > targets/my-nixos/hardware-configuration.nix
```

Add the target to `flake.nix` under `nixosConfigurations` following the same pattern as `zero`.

## Decision Guide: Takeout Container vs Heirloom

| Factor | Takeout Container | Heirloom |
|--------|-------------------|----------|
| Target name in flake | Generic (`type-server`) | Named (`zero`, `my-workstation`) |
| Hardware config | nixos-facter (auto-detected) | `hardware-configuration.nix` per target |
| Disk layout | Pre-defined disko layout | Custom disk configuration |
| Replacement strategy | Clone + redeploy | Repair existing machine |

## What You've Done

- Built an installer USB with the custom TUI image
- Booted into the live environment
- Selected a configuration (takeout container or heirloom)
- Installed NixOS with automatic disk partitioning and hardware detection
- Verified SSH access and system configuration

## Next Steps

- **[Add Secrets with opnix](getting-started-opnix.md)** — Configure 1Password secrets management on your NixOS machine
- **[Deploy MicroVMs](../how-to/manage-microvms.md)** — If using `type-server`, you can host lightweight VMs
- **Read [Disposable Infrastructure](../explanation/disposable-infrastructure.md)** — Understand the takeout container pattern in depth
