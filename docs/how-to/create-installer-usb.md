# Create a NixOS Installer USB

How to build and use the NixOS installer ISO with guided installation from your flake.

## Overview

The NixOS installer ISO provides a guided, menu-driven installation experience that:
- Boots into a TUI (Terminal User Interface) using `gum`
- Automatically uses your flake configuration from GitHub
- Falls back to a bundled flake copy if network is unavailable
- Uses `disko` for declarative disk partitioning
- Supports both "cattle" (type-*) and "pet" (named host) configurations

## Build the ISO

**Note:** The ISO must be built on a Linux system (or NixOS).

### Option 1: Build with Nix (requires Linux)

```bash
# Build the ISO
nix build .#iso

# The ISO will be in result/iso/
ls -la result/iso/
```

### Option 2: Build remotely via SSH

From macOS or another system with SSH access to a Linux machine:

```bash
# Build on a remote Linux builder
nix build .#iso --builders "ssh://user@linux-builder x86_64-linux"
```

### Option 3: Use GitHub Actions

Add a workflow to build the ISO automatically:

```yaml
# .github/workflows/build-iso.yml
name: Build Installer ISO
on:
  workflow_dispatch:
  push:
    branches: [main]
    paths:
      - 'targets/installer-iso/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - run: nix build .#iso
      - uses: actions/upload-artifact@v4
        with:
          name: nixos-installer-iso
          path: result/iso/*.iso
```

## Flash the ISO to USB

### macOS

```bash
# Identify USB drive (be careful!)
diskutil list

# Unmount the drive
diskutil unmountDisk /dev/diskX

# Flash the ISO (replace diskX with your drive)
# Note: macOS uses 'M' (uppercase) for megabytes
sudo dd if=result/iso/*.iso of=/dev/rdiskX bs=4M

# Eject
diskutil eject /dev/diskX
```

### Linux

```bash
# Identify USB drive
lsblk

# Flash the ISO (replace sdX with your drive)
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress

# Or use a GUI tool like Etcher or USBImager
```

## Boot and Install

1. **Insert USB** into target machine
2. **Boot from USB** (may need to press F12, F2, or Del for boot menu)
3. **Select installer** from boot menu
4. **Wait for auto-login** - the installer will start automatically on TTY1

### Installation Flow

```
Welcome Screen
    ↓
Step 1: Enter Hostname
    ↓
Step 2: Select Target
    • type-desktop  (cattle pattern)
    • type-server   (cattle pattern)  
    • bootstrap     (minimal)
    • Existing host (if found)
    ↓
Step 3: Select Disk
    (Shows available disks with size/model)
    ↓
Step 4: Review & Confirm
    ↓
Installation Progress
    ↓
Success! Remove USB and reboot
```

## Network vs Offline Mode

### Network Mode (Default)

If the installer detects network connectivity:
- Uses `github:funkymonkeymonk/nix` (latest)
- Downloads packages from cache.nixos.org
- Can access all latest configurations

### Offline Mode (Fallback)

If no network is available:
- Uses the flake bundled in `/iso/nix-flake/`
- Works entirely offline
- May have older package versions

## SSH Access During Install

The installer enables SSH with your public key pre-configured:

```bash
# From another machine
ssh root@<installer-ip>

# Password is empty, SSH key auth only
```

Useful for:
- Remote assistance during install
- Debugging installation issues
- Copying the generated hardware-configuration.nix

## Post-Installation

### If using "bootstrap" target:

1. System boots into minimal NixOS
2. Copy hardware config:
   ```bash
   sudo cp /etc/nixos/hardware-configuration.nix /root/
   ```
3. Create a proper target in your flake
4. Apply full configuration:
   ```bash
   sudo nixos-rebuild switch --flake github:funkymonkeymonk/nix#<hostname>
   ```

### If using type-server or type-desktop (takeout containers):

System boots fully configured with auto-updates from GitHub. Just:
1. SSH in: `ssh monkey@<hostname>` (hostname assigned via DHCP)
2. Verify everything works
3. Done! The system auto-updates daily at 02:00

### If using existing heirloom target (e.g., "zero"):

System boots fully configured. Just:
1. Set passwords
2. Verify everything works
3. Enjoy your new NixOS system!

## Troubleshooting

### ISO won't boot
- Check BIOS/UEFI settings
- Try different USB port
- Verify ISO checksum: `sha256sum result/iso/*.iso`

### Installer can't find disk
- Run `lsblk` to verify disk detection
- Try different SATA/NVMe ports
- Check for RAID mode in BIOS (should be AHCI)

### Network not working
- Installer will use local flake automatically
- For Wi-Fi: use `nmtui` to configure before starting installer

### Installation fails
- Check disk isn't mounted: `umount -R /mnt`
- Try manual partitioning first
- Review logs: `journalctl -xe`

## Advanced Usage

### Custom ISO Configuration

Edit `targets/installer-iso/default.nix` to:
- Add more packages
- Change default settings
- Include custom scripts

### Pre-seed Configuration

Create a file `targets/installer-iso/answers.json`:

```json
{
  "hostname": "myserver",
  "target": "type-server",
  "disk": "/dev/sda"
}
```

Modify installer to read this for unattended installs.

### Multiple Disks

The current installer uses a single disk. For complex layouts:
1. Use "bootstrap" mode
2. Manually configure disko after install
3. Or modify `disk-configs/single-disk-ext4.nix`

## Related

- [Add a new machine](add-machine.md)
- [NixOS Installation Manual](https://nixos.org/manual/nixos/stable/#sec-installation)
- [disko documentation](https://github.com/nix-community/disko)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)