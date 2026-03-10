# Cattle Infrastructure - Automated NixOS Installation

This directory contains the "cattle" approach to NixOS management: generic machine types with automatic hardware detection. No more per-machine `hardware-configuration.nix` files!

## Philosophy: Pets vs Cattle

- **Pets**: Each machine is unique, hand-configured, named, and cared for individually
- **Cattle**: Machines are identical, interchangeable, and managed as a group

Your existing `zero` config is a pet. The `type-*` configs here are cattle.

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
- Headless server
- Minimal packages
- SSH only
- No desktop

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

### Option 1: Keep Pets + Add Cattle (Recommended)

Keep `zero` as-is. Use cattle for new machines:

```nix
nixosConfigurations = {
  # Existing (pets) - keep working
  zero = mkNixosHost { ... };
  
  # New machines (cattle)
  type-desktop = nixpkgs.lib.nixosSystem { ... };
  type-server = nixpkgs.lib.nixosSystem { ... };
};
```

### Option 2: Full Migration

Convert everything to cattle:

1. Backup data from zero
2. Reinstall using cattle
3. Restore data
4. Delete old pet configs

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

After installation, you'll have a minimal system. To apply your full configuration:

```bash
# SSH into new machine
ssh root@192.168.1.100

# Copy the generated facter.json
nixos-facter > /etc/nixos/facter.json

# Or apply from your flake
nixos-rebuild switch --flake github:youruser/nix#your-host
```

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

| Before (Pets) | After (Cattle) |
|---------------|----------------|
| `hardware-configuration.nix` per machine | ❌ None - auto-detected |
| Manual partitioning | ❌ Automated |
| 30+ minute install | ✅ 5 minute install |
| Per-machine SSH keys | ✅ Auto-generated |
| Can't build remotely | ✅ Pure flake - build anywhere |
| CI uses stubs | ✅ CI tests real configs |

## See Also

- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) - Remote installation
- [disko](https://github.com/nix-community/disko) - Declarative partitioning
- [nixos-facter](https://github.com/nix-community/nixos-facter) - Hardware detection
