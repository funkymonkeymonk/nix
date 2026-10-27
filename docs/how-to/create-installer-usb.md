# Create an SSH-ready NixOS installer USB

The repository ISO is a minimal NixOS live target, not an interactive disk
installer. It boots with networking and SSH, reports its current addresses and
host-key fingerprint, and leaves machine selection, review, credentials, and
installation to the workstation's named devenv Machines operation. The ISO
helper never partitions, formats, or installs a local disk. The USB-writing
step is manual; the build and helper never write to a block device.

## Build the ISO

Build on x86_64-linux (or use a configured remote Linux builder from macOS):

```sh
nix build .#iso
ls -lh result/iso/
```

From a macOS workstation with an SSH builder configured, the build can be
forwarded to Linux, for example:

```sh
nix build .#iso --builders 'ssh://user@linux-builder x86_64-linux'
```

## Flash a USB drive

> **DESTRUCTIVE: choosing the wrong block device will destroy all data on that
drive.** Identify and verify the USB device by size/model before continuing.
> Never copy the example device names blindly. Unplug other removable drives
> where practical, and double-check the `of=` destination immediately before
> running `dd`.

On macOS, inspect the device with `diskutil list`, then substitute the verified
whole-disk identifier in both commands:

```sh
 diskutil unmountDisk /dev/diskX
 sudo dd if=result/iso/*.iso of=/dev/rdiskX bs=4M
 diskutil eject /dev/diskX
```

On Linux, inspect with `lsblk -o NAME,SIZE,MODEL,TYPE`, then substitute the
verified whole-disk device (not a partition):

```sh
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

No USB device is written by the build or by the readiness helper.

## Boot and connect

1. Boot the target from the USB using its firmware boot menu.
2. On local TTY1, the `installer-ready` report runs automatically after boot
   and autologin. It shows globally scoped network addresses, SSH service
   status, the SSH host-key fingerprint, and a read-only block-device inventory.
   The same usage instructions are available in the SSH login MOTD.
3. Verify the displayed SSH host-key fingerprint over a trusted channel before
   trusting the target or connecting. Do not accept an unexpected fingerprint.
4. On the workstation, configure the SSH endpoint in the ignored
   `devenv.local.nix` file. For example:

   ```nix
   {...}: {
     machines.zero.target.host = "192.0.2.25";
   }
   ```

   Use the actual address reported by the target, or a verified SSH alias.
5. From the workstation, run the explicit named install task:

   ```sh
   devenv tasks run machines:install --input machine=zero
   ```

   Replace `zero` with the one intended catalog machine. The operation is
   destructive to the target's disk; review the selected machine and its
   installation plan before confirming. The workstation is responsible for
   machine selection, SecretSpec/1Password access, review, and installation.
   No machine credentials or private keys are transferred into the ISO.

Run `installer-ready` from an SSH session to refresh the current address,
service, and fingerprint report. The ISO retains the existing public-key SSH
policy: root SSH is limited to key authentication, password authentication is
disabled, and the configured authorized public key is unchanged. Do not weaken
root SSH or sudo policy as part of installation setup.

**Machines NixOS installation requires root SSH.** Existing headless NixOS
roles currently deny root login. They are not ready for remote Machines
installation until access is configured and approved separately; this guide
does not change their SSH or sudo settings.

## Hardware facts and secrets

`devenv build machines.zero.build.nixos` (and equivalent NixOS machine builds)
requires `.machines/<name>/facter.json` when that machine enables facter.
`devenv machines install` generates the report from the target hardware. Do not
fabricate, copy, or commit a guessed report. If a hand-written
`hardware-configuration.nix` is used instead, import that real file in the
machine's local NixOS module and explicitly disable facter locally, for example:

```nix
{lib, ...}: {
  hardware.facter.reportPath = lib.mkForce null;
}
```

SecretSpec's Homelab and Personal provider profiles are configured but
intentionally contain no secret values. Secret-dependent operations should
run only after the owner adds a real, confirmed item/field reference from the
machine's default vault. Fresh-host install fails closed until
`OPNIX_SERVICE_ACCOUNT_TOKEN` is declared with an approved reference. The ISO
can be built without these values, but the USB install path is not ready for
production until the access, Facter, credential, and physical smoke-test
prerequisites are resolved.

## Compatibility and troubleshooting

The standalone legacy installer (`nix run .#installer`) and the old ISO
installer source remain available as fallback material while the new flow is
validated. Do not delete them until the physical USB smoke test and the
credential/access prerequisites have passed. The SSH-ready ISO does not
autostart either legacy installer.

- **No address appears:** check the Ethernet link, DHCP service, or configure
  networking from another local shell before retrying `installer-ready`.
- **SSH is not active:** inspect `systemctl status sshd.service` locally.
- **Fingerprint is unavailable:** wait for the live system's SSH host keys to
  be generated, then run `installer-ready` again.
- **ISO does not boot:** verify the ISO checksum and check the firmware's USB
  boot settings.
- **Install prerequisites are missing:** resolve the named machine's target
  and required workstation-side configuration before invoking the install
  task. Do not work around missing facts or credentials by adding them to the
  ISO.
