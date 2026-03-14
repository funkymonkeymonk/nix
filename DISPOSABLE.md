# Disposable Infrastructure - Automated NixOS Installation

This directory contains the "takeout container" approach to NixOS management: generic machine types with automatic hardware detection. No more per-machine `hardware-configuration.nix` files!

## Philosophy: Heirloom Dishes vs Takeout Containers

- **Heirloom Dishes**: Each machine is unique, hand-crafted, named, and cared for individually. If it breaks, you repair it. You know its history.
- **Takeout Containers**: Machines are standardized, disposable, and interchangeable. If one has a problem, you throw it away and grab another. You don't care which specific one you get.

Your existing `zero` config is an heirloom dish. The `type-*` configs here are takeout containers.

## Quick Start

### Interactive TUI Installer

The installer uses a beautiful ncurses-style TUI powered by [gum](https://github.com/charmbracelet/gum) from Charm.

```bash
# Boot target machine from NixOS USB installer
# Set password: passwd
# Check IP: ip addr

# From your Mac (MegamanX):
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

### Manual/Non-Interactive Mode

For automation or scripting, you can still use the traditional command-line approach by modifying the script or using nixos-anywhere directly.

## Machine Types

### `type-desktop`
- Gaming/workstation setup
- GNOME desktop
- NVIDIA/AMD/Intel graphics (auto-detected)
- Steam, audio, networking
- SSH enabled

### `type-server`
- Headless server (takeout pattern - no hardcoded hostname)
- MicroVM host support (qemu, virtiofsd, KVM)
- Hardened SSH (keys only, no root login)
- Auto-upgrade from GitHub daily at 02:00
- Firewall with SSH access
- Hostname assigned via DHCP
- No desktop environment

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│  Your Flake                                             │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Machine Types (Generic)                                │
│  ├─ type-desktop.nix   ← Gaming/GUI config             │
│  └─ type-server.nix    ← Headless config               │
│                                                         │
  │  Disk Layouts                                           │
  │  └─ single-disk-ext4.nix                               │
│                                                         │
│  Hardware Detection                                     │
│  └─ nixos-facter       ← Auto-detects everything       │
│                                                         │
│  Installation                                           │
│  └─ nixos-anywhere     ← One-command remote install    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### The Magic: nixos-facter

Instead of `hardware-configuration.nix`, we use `nixos-facter`:

```json
// Generated during install: facter.json
{
  "hardware": {
    "cpu": { "vendor": "GenuineIntel", "features": [...] },
    "graphics": { "cards": [{ "vendor": "NVIDIA", ... }] },
    "kernel_modules": ["nvidia", "nvidia_modeset", ...]
  }
}
```

This auto-configures:
- ✅ Kernel modules
- ✅ Graphics drivers
- ✅ Firmware
- ✅ Network drivers
- ✅ All hardware detection

### The Magic: disko

Instead of `fileSystems` in `hardware-configuration.nix`:

```nix
# disk-configs/single-disk-ext4.nix
disko.devices = {
  disk.main = {
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = { ... };      # /boot
        root = { ... };     # /
      };
    };
  };
};
```

## Migration Path

### Option 1: Keep Heirlooms + Add Takeout Containers (Recommended)

Keep `zero` as-is. Use takeout containers for new machines:

```nix
nixosConfigurations = {
  # Existing (heirlooms) - keep working
  zero = mkNixosHost { ... };
  
  # New machines (takeout) - pure, no per-machine config needed
  type-desktop = nixpkgs.lib.nixosSystem { ... };
  type-server = nixpkgs.lib.nixosSystem { ... };  # Hostname from DHCP
};
```

**Key difference**: Takeout container machines don't need `targets/<hostname>/` directories. The hostname comes from DHCP, not the flake.

### Option 2: Full Migration

Convert everything to takeout containers:

1. Backup data from zero
2. Reinstall using takeout container approach
3. Restore data
4. Delete old heirloom configs

## Installation Details

### Prerequisites

- Target machine booted with NixOS installer
- SSH enabled on target (run `systemctl start sshd` and `passwd`)
- `gum` installed in your environment (provided by devenv)

### Interactive Features

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

### Post-Install

#### For Takeout Container Machines (type-desktop, type-server)

These are ready to use immediately! The configuration is pure and self-contained:

```bash
# SSH into new machine
ssh monkey@<hostname>  # Hostname assigned via DHCP

# System is already fully configured and auto-updating from GitHub
```

#### For Heirloom Machines (bootstrap → named host)

If you used bootstrap to create an heirloom machine:

```bash
# SSH into new machine
ssh root@192.168.1.100

# Copy the generated facter.json
nixos-facter > /etc/nixos/facter.json

# Create a proper target in your flake (see add-machine.md)
nixos-rebuild switch --flake github:youruser/nix#<hostname>
```

## Hostnames and DHCP

Takeout container machines don't have hardcoded hostnames in the flake. Instead, hostnames come from:

1. **DHCP server** (recommended) - Configure your router/dhcpd to assign hostnames by MAC address
2. **Local override** - Create `/etc/nixos/local.nix` on the machine (outside flake)

Example DHCP configuration (dnsmasq):
```
dhcp-host=aa:bb:cc:dd:ee:ff,drlight,192.168.1.50,infinite
```

This keeps all "heirloom" metadata (names, IPs) out of the flake.

## Customization

### Add a New Machine Type

1. Create `machine-types/my-type.nix`
2. Add to `flake.nix`:

```nix
"type-my-type" = nixpkgs.lib.nixosSystem {
  modules = [
    inputs.disko.nixosModules.disko
    ./disk-configs/my-layout.nix
    inputs.nixos-facter.nixosModules.facter
    ./machine-types/my-type.nix
    # ... other modules
  ];
};
```

### Custom Disk Layout

See [disko examples](https://github.com/nix-community/disko/tree/master/example) for:
- ZFS
- BTRFS with subvolumes
- RAID arrays
- Multiple disks

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

## Benefits

| Before (Heirlooms) | After (Takeout Containers) |
|---------------------|---------------------------|
| `hardware-configuration.nix` per machine | ❌ None - auto-detected |
| Manual partitioning | ❌ Automated |
| Per-machine target directories | ❌ Just use type-* |
| Hostname in flake | ❌ From DHCP |
| Impure builds (local paths) | ✅ Pure GitHub builds |
| 30+ minute install | ✅ 5 minute install |
| Per-machine SSH keys | ✅ Auto-generated |
| Can't build remotely | ✅ Pure flake - build anywhere |
| CI uses stubs | ✅ CI tests real configs |

## See Also

- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) - Remote installation
- [disko](https://github.com/nix-community/disko) - Declarative partitioning
- [nixos-facter](https://github.com/nix-community/nixos-facter) - Hardware detection
