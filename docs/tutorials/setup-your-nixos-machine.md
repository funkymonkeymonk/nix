---
title: "Set Up Your NixOS Machine"
description: "Build the SSH-ready live image and install one named NixOS machine from a workstation"
type: tutorial
audience: both
last-reviewed: 2026-10-25
---

# Set Up Your NixOS Machine

This walkthrough uses the SSH-ready NixOS live USB as a remote target. The
workstation selects and installs one named machine with devenv Machines; the
live image does not partition or install a disk itself. Use only a disposable
VM or disk until the access, credentials, and physical USB prerequisites below
are approved and tested.

## Prerequisites

- A Linux workstation, or a macOS workstation with a configured remote Linux
  builder, to build the x86_64-linux ISO
- A USB drive whose whole-disk device can be positively identified
- A reviewed SSH public-key access policy and a trusted way to verify the live
  host-key fingerprint
- An explicitly selected Machines catalog target and, for NixOS, a valid
  hardware report or an intentionally configured hand-written hardware module

Fresh-host installation also requires root SSH access and the approved
`OPNIX_SERVICE_ACCOUNT_TOKEN` SecretSpec reference. Those prerequisites are not
currently met for production: the committed profiles contain no secret values,
and the existing headless NixOS roles deny root login. Do not weaken SSH or
sudo policy or substitute a guessed secret to get past these guards.

## Step 1: Build the ISO and safely flash a USB

Build the live image on Linux, or forward the build to a configured Linux
builder from macOS:

```sh
nix build .#iso
# Or, from macOS with a configured Linux builder:
nix build .#iso --builders 'ssh://user@linux-builder x86_64-linux'
```

Before writing anything, inspect the block-device inventory and verify the
whole-disk device by size and model. The following commands are examples only;
never copy a device name without confirming it is the USB drive:

```sh
# Linux: inspect first, then replace /dev/sdX with the verified whole disk.
lsblk -o NAME,SIZE,MODEL,TYPE
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

On macOS, inspect with `diskutil list`, then unmount, write to the verified
whole-disk device, and eject it. No build task or installer helper writes to a
USB device automatically.

## Step 2: Boot and verify the live target

1. Boot from the USB using the target firmware's boot menu.
2. After boot, local TTY1 automatically prints `installer-ready`. The same
   usage instructions appear in the SSH login MOTD. The helper reports global
   network addresses, sshd status, the host-key fingerprint, and a read-only
   inventory of available disks; it does not partition, format, or install.
3. Verify the reported SSH host-key fingerprint over a trusted channel before
   trusting or connecting to the target. Do not accept an unexpected key.
4. Add the verified endpoint to the ignored local `devenv.local.nix` override
   (or use a verified SSH alias), not a committed target file:

   ```nix
   {...}: {
     machines.zero.target.host = "192.0.2.25";
   }
   ```

   Substitute the actual address shown by the live target.

## Step 3: Install one named machine from the workstation

After confirming the selected machine and target, run the explicitly named
workstation task:

```sh
devenv tasks run machines:install --input machine=zero
```

The task warns that installation is destructive to the target disk and asks
for explicit confirmation. Review the machine's install plan and ensure its
storage mapping points only at the disposable VM disk before testing. There is
no implicit fleet install.

Machines NixOS installation requires root SSH. The ISO preserves its current
key-only root access policy; existing headless NixOS roles currently deny root
login and must not be treated as deployable until their access is separately
configured and approved. This task does not relax root SSH or sudo policy.

## Hardware facts and secrets

A build such as `devenv build machines.zero.build.nixos` requires
`.machines/zero/facter.json` when that machine enables facter. The named
`machines install` workflow generates this report from the target. Do not
fabricate, copy from another host, or commit a guessed report. If a real
hand-written `hardware-configuration.nix` is used instead, import it in the
machine's local NixOS module and explicitly disable facter locally, for
example:

```nix
{lib, ...}: {
  hardware.facter.reportPath = lib.mkForce null;
}
```

SecretSpec's Homelab and Personal provider profiles are configured but
intentionally contain no values. Secret-dependent operations may run only
after the owner confirms a real item/field reference in that machine's default
vault. Fresh-host installation fails closed until
`OPNIX_SERVICE_ACCOUNT_TOKEN` is declared with an approved reference. Do not
query 1Password or insert a guessed reference as part of this walkthrough. The
USB workflow is not ready for production until this credential, approved
access, Facter, and physical USB smoke prerequisites are met.

## Step 4: Verify the installed system

After a separately approved disposable install completes, reboot the VM from
its virtual disk and verify its expected hostname, SSH access, and system
configuration. Keep the USB and disposable disk available until the machine is
confirmed healthy. Do not use production disks for this smoke test.

## Compatibility fallback

The standalone legacy installer (`nix run .#installer`) and the old installer
source files remain available as compatibility fallback. They are not
started by the SSH-ready image and must not be removed until the physical USB
smoke test and access/credential prerequisites are satisfied.
