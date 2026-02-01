# ZFS External Hard Drives Setup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Set up two external USB-C hard drives with ZFS on MegamanX for data storage with production-grade features including encryption, snapshots, and monitoring.

**Architecture:** Create a ZFS pool with two external drives, configure encryption, set up automated snapshots, and integrate monitoring. The setup will be portable to drlight (Linux) when drives are moved.

**Tech Stack:** ZFS on macOS (OpenZFS), Nix configuration management, systemd-style services (via launchd on macOS), monitoring tools

---

### Task 1: Create ZFS NixOS-style module for Darwin

**Files:**
- Create: `modules/common/zfs.nix`

**Step 1: Write the ZFS module configuration**

```nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.myConfig.zfs;
in {
  options.myConfig.zfs = {
    enable = mkEnableOption "ZFS filesystem support";
    
    pools = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          devices = mkOption {
            type = types.listOf types.str;
            description = "List of devices in the pool";
          };
          
          mountpoint = mkOption {
            type = types.str;
            description = "Default mountpoint for the pool";
            default = "/mnt";
          };
          
          encryption = mkOption {
            type = types.bool;
            description = "Enable pool encryption";
            default = false;
          };
          
          compression = mkOption {
            type = types.str;
            description = "Compression algorithm";
            default = "lz4";
          };
          
          snapshots = mkOption {
            type = types.bool;
            description = "Enable automatic snapshots";
            default = false;
          };
          
          snapshotRetention = mkOption {
            type = types.int;
            description = "Number of snapshots to retain";
            default = 30;
          };
        };
      });
      default = {};
    };
  };

  config = mkIf cfg.enable {
    # OpenZFS package for macOS
    environment.systemPackages = with pkgs; [
      openzfs
    ];

    # Load ZFS kernel extension (kext)
    system.activationScripts.postActivation.text = ''
      # Load ZFS kernel extension
      if ! kextstat | grep -q org.openzfs.zfs; then
        sudo kextload -b org.openzfs.zfs
      fi
    '';

    # Enable ZFS services
    launchd.daemons = {
      zfs = {
        script = ''
          # Start ZFS services
          /run/current-system/sw/bin/zpool import -a
          /run/current-system/sw/bin/zfs mount -a
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = true;
          StandardErrorPath = "/var/log/zfs.log";
          StandardOutPath = "/var/log/zfs.log";
        };
      };

      zfs-snapshot = mkIf (any (pool: pool.snapshots) (attrValues cfg.pools)) {
        script = ''
          # Create hourly snapshots
          ${lib.concatMapStringsSep "\n" (poolName: 
            let pool = cfg.pools.${poolName}; in
            lib.optionalString pool.snapshots ''
              /run/current-system/sw/bin/zfs snapshot ${poolName}@$(date +%Y%m%d_%H%M%S)
              
              # Clean up old snapshots
              /run/current-system/sw/bin/zfs list -t snapshot -o name ${poolName}@ | \
                tail -n +$((${pool.snapshotRetention} + 2)) | \
                xargs -I {} /run/current-system/sw/bin/zfs destroy {}
            ''
          ) (attrNames cfg.pools)}
        '';
        serviceConfig = {
          StartInterval = 3600; # Every hour
          StandardErrorPath = "/var/log/zfs-snapshot.log";
          StandardOutPath = "/var/log/zfs-snapshot.log";
        };
      };
    };

    # Create ZFS monitoring script
    environment.shellAliases = {
      zfs-status = ''
        ${pkgs.openzfs}/bin/zpool status && ${pkgs.openzfs}/bin/zfs list
      '';
      zfs-health = ''
        ${pkgs.openzfs}/bin/zpool status -x
      '';
    };
  };
}
```

**Step 2: Run test to verify module syntax**

Run: `nix-instantiate --eval --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; in (import ./modules/common/zfs.nix { inherit config lib pkgs; })'`
Expected: Success with no syntax errors

**Step 3: Commit**

```bash
git add modules/common/zfs.nix
git commit -m "feat: add ZFS module for Darwin with encryption and snapshots"
```

### Task 2: Add ZFS bundle configuration

**Files:**
- Modify: `bundles.nix:154-175`

**Step 1: Add ZFS bundle to bundles.nix**

Find the `agent-skills` bundle section and add after it:

```nix
    zfs = {
      packages = with pkgs; [
        openzfs
      ];

      config = {
        # ZFS-specific shell aliases
        environment.shellAliases = {
          zfs-pools = "zpool list";
          zfs-datasets = "zfs list";
          zfs-snapshots = "zfs list -t snapshot";
          zfs-health = "zpool status -x";
          zfs-scrub = "sudo zpool scrub";
        };
      };
    };
```

**Step 2: Run test to verify bundle syntax**

Run: `nix-instantiate --eval --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; in (import ./bundles.nix { inherit pkgs lib; })'`
Expected: Success with no syntax errors

**Step 3: Commit**

```bash
git add bundles.nix
git commit -m "feat: add ZFS bundle with management aliases"
```

### Task 3: Create MegamanX hardware configuration for ZFS

**Files:**
- Create: `targets/megamanx/default.nix`
- Create: `targets/megamanx/hardware-configuration.nix`

**Step 1: Create target directory structure**

Run: `mkdir -p targets/megamanx`

**Step 2: Create MegamanX target configuration**

```nix
{
  config,
  lib,
  pkgs,
  ...
}: {
  # ZFS configuration for external drives
  myConfig.zfs = {
    enable = true;
    
    pools = {
      # Main data pool for external drives
      "data_pool" = {
        devices = [
          # These will be updated with actual device paths
          "disk1"  
          "disk2"
        ];
        mountpoint = "/Volumes/data_pool";
        encryption = true;
        compression = "lz4";
        snapshots = true;
        snapshotRetention = 30;
      };
    };
  };

  # Additional macOS-specific ZFS settings
  environment.systemPackages = with pkgs; [
    # Add ZFS monitoring tools
    htop
    iotop
  ];
}
```

**Step 3: Create hardware configuration template**

```nix
{
  # Hardware configuration for MegamanX
  # This file will be updated with actual device paths
  # when the external drives are connected
  
  # USB device paths will be added here after connecting drives
  # Example format:
  # fileSystems."/Volumes/data_pool" = {
  #   device = "data_pool";
  #   fsType = "zfs";
  # };
}
```

**Step 4: Run test to verify configuration syntax**

Run: `nix-instantiate --eval --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; in (import ./targets/megamanx/default.nix { inherit config lib pkgs; })'`
Expected: Success with no syntax errors

**Step 5: Commit**

```bash
git add targets/megamanx/
git commit -m "feat: add MegamanX target configuration for ZFS"
```

### Task 4: Update flake.nix to include MegamanX target and ZFS module

**Files:**
- Modify: `flake.nix:204-249`

**Step 1: Add ZFS module to MegamanX configuration**

In the MegamanX darwinConfiguration, find the modules list and add ZFS:

```nix
      modules = [
        mac-app-util.darwinModules.default
        nix-homebrew.darwinModules.nix-homebrew
        configuration
        ./modules/common/options.nix
        ./modules/common/users.nix
        ./modules/common/shell.nix
        ./modules/common/onepassword.nix
        ./modules/common/zfs.nix  # Add this line
        ./os/darwin.nix
        ./modules/home-manager/aerospace.nix
        (mkBundleModule "darwin" ["developer" "desktop" "workstation" "entertainment" "megamanx_llm_host" "zfs"])  # Add "zfs"
        {
          # ... existing configuration
        }
      ];
```

**Step 2: Add MegamanX target import**

Add after the existing imports in the module list:

```nix
        ./targets/megamanx  # Add this line
```

**Step 3: Run test to verify flake syntax**

Run: `nix flake check`
Expected: Success with no errors

**Step 4: Commit**

```bash
git add flake.nix
git commit -m "feat: integrate ZFS module and target into MegamanX configuration"
```

### Task 5: Create ZFS setup and management scripts

**Files:**
- Create: `scripts/zfs-setup.sh`
- Create: `scripts/zfs-migrate.sh`

**Step 1: Create ZFS setup script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ZFS External Drives Setup Script for MegamanX
# This script configures two external USB-C drives with ZFS

echo "🔧 ZFS External Drives Setup for MegamanX"

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ This script is designed for macOS (Darwin)"
    exit 1
fi

# Check if OpenZFS is installed
if ! command -v zpool &> /dev/null; then
    echo "❌ OpenZFS not found. Please install via Nix configuration first."
    exit 1
fi

# Function to list available disks
list_disks() {
    echo "📁 Available external disks:"
    diskutil list external | grep -E "(disk[0-9]+)" | awk '{print $1}' | sort -u
}

# Function to get disk info
get_disk_info() {
    local disk=$1
    echo "📊 Information for $disk:"
    diskutil info "$disk" | grep -E "(Device Node|Device / Media Name|Size|Protocol)"
}

# Show available disks
echo
list_disks
echo

# Get disk paths from user
read -p "Enter first external disk path (e.g., disk3): " DISK1
read -p "Enter second external disk path (e.g., disk4): " DISK2

# Validate disk paths
for disk in "$DISK1" "$DISK2"; do
    if [[ ! -b "/dev/$disk" ]]; then
        echo "❌ Disk /dev/$disk not found"
        exit 1
    fi
    get_disk_info "$disk"
    echo
done

# Confirm with user
echo "⚠️  This will ERASE ALL DATA on /dev/$DISK1 and /dev/$DISK2"
read -p "Continue? (type 'yes' to confirm): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "❌ Setup cancelled"
    exit 1
fi

# Create ZFS pool with encryption
echo "🔒 Creating encrypted ZFS pool..."
sudo zpool create \
    -o ashift=12 \
    -O compression=lz4 \
    -O encryption=on \
    -O keyformat=passphrase \
    -O keylocation=prompt \
    -o autoexpand=on \
    -o autoreplace=on \
    data_pool \
    mirror \
    "/dev/$DISK1" \
    "/dev/$DISK2"

# Create datasets
echo "📁 Creating datasets..."
sudo zfs create data_pool/data
sudo zfs create data_pool/backups
sudo zfs create data_pool/media

# Set mountpoints
sudo zfs set mountpoint="/Volumes/data_pool/data" data_pool/data
sudo zfs set mountpoint="/Volumes/data_pool/backups" data_pool/backups  
sudo zfs set mountpoint="/Volumes/data_pool/media" data_pool/media

# Enable automatic snapshots
echo "📸 Setting up automatic snapshots..."
sudo zfs set com.sun:auto-snapshot=true data_pool
sudo zfs set com.sun:auto-snapshot:true data_pool/data
sudo zfs set com.sun:auto-snapshot:true data_pool/backups
sudo zfs set com.sun:auto-snapshot:true data_pool/media

# Create first snapshot
sudo zfs snapshot data_pool@initial

echo "✅ ZFS pool 'data_pool' created successfully!"
echo "📍 Mountpoint: /Volumes/data_pool"
echo "🔑 Encryption: Enabled with passphrase"
echo "📸 Snapshots: Enabled"
echo
echo "To check status:"
echo "  zfs-status"
echo "  zfs-health"
echo
echo "To mount on Linux (drlight):"
echo "  sudo zpool import data_pool"
```

**Step 2: Create migration script for drlight**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ZFS Migration Script for Moving Drives to drlight (Linux)
# This script prepares the external drives for migration to Linux

echo "🚀 ZFS Migration to drlight (Linux)"

# Check if pool exists
if ! zpool list data_pool &> /dev/null; then
    echo "❌ ZFS pool 'data_pool' not found"
    exit 1
fi

# Export pool for safe removal
echo "📤 Exporting ZFS pool..."
sudo zpool export data_pool

echo "✅ Pool exported safely. Drives can now be moved to drlight."
echo
echo "On drlight (Linux), run:"
echo "  sudo zpool import data_pool"
echo "  sudo zfs mount -a"
echo
echo "Drives are ready for migration! 🎯"
```

**Step 3: Make scripts executable**

Run: `chmod +x scripts/zfs-setup.sh scripts/zfs-migrate.sh`

**Step 4: Commit**

```bash
git add scripts/
git commit -m "feat: add ZFS setup and migration scripts"
```

### Task 6: Add ZFS tasks to Taskfile.yml

**Files:**
- Modify: `Taskfile.yml`

**Step 1: Add ZFS tasks to Taskfile.yml**

```yaml
  zfs:setup:
    desc: "Setup ZFS external drives on MegamanX"
    run: once
    preconditions:
      - sh: "uname | grep -q Darwin"
        msg: "This task only runs on macOS (MegamanX)"
    cmds:
      - "./scripts/zfs-setup.sh"

  zfs:status:
    desc: "Check ZFS pool and dataset status"
    run: once
    cmds:
      - "zpool status"
      - "zfs list"

  zfs:health:
    desc: "Check ZFS system health"
    run: once
    cmds:
      - "zpool status -x"

  zfs:migrate:
    desc: "Prepare ZFS drives for migration to drlight"
    run: once
    cmds:
      - "./scripts/zfs-migrate.sh"

  zfs:snapshot:
    desc: "Create manual ZFS snapshot"
    run: once
    cmds:
      - "sudo zfs snapshot data_pool@manual_$(date +%Y%m%d_%H%M%S)"

  zfs:scrub:
    desc: "Start ZFS scrub for data integrity"
    run: once
    cmds:
      - "sudo zpool scrub data_pool"
```

**Step 2: Run test to validate Taskfile syntax**

Run: `task --list | grep zfs`
Expected: Shows the new ZFS tasks

**Step 3: Commit**

```bash
git add Taskfile.yml
git commit -m "feat: add ZFS management tasks"
```

### Task 7: Update documentation

**Files:**
- Create: `docs/zfs-setup.md`

**Step 1: Create ZFS documentation**

```markdown
# ZFS External Hard Drives Setup

This guide covers setting up two external USB-C hard drives with ZFS on MegamanX for data storage with production-grade features.

## Overview

- **Pool Name**: `data_pool`
- **Configuration**: Mirror (RAID-1) with two drives
- **Encryption**: AES-256 with passphrase
- **Compression**: LZ4
- **Snapshots**: Automatic (1-hour intervals)
- **Retention**: 30 snapshots

## Quick Setup

1. **Build and apply configuration**:
   ```bash
   # On MegamanX
   task build:darwin:MegamanX
   darwin-rebuild switch
   ```

2. **Connect external drives** and run setup:
   ```bash
   task zfs:setup
   ```

3. **Verify setup**:
   ```bash
   task zfs:status
   task zfs:health
   ```

## Available Tasks

| Task | Description |
|------|-------------|
| `task zfs:setup` | Initial setup of external drives |
| `task zfs:status` | Check pool and dataset status |
| `task zfs:health` | Check system health |
| `task zfs:scrub` | Start data integrity scrub |
| `task zfs:snapshot` | Create manual snapshot |
| `task zfs:migrate` | Prepare drives for migration |

## Dataset Structure

```
/Volumes/data_pool/
├── data/          # General data storage
├── backups/       # Backup files
└── media/         # Media files (photos, videos)
```

## Migration to drlight (Linux)

When ready to move drives to drlight:

1. **Export from MegamanX**:
   ```bash
   task zfs:migrate
   ```

2. **Physically move drives** to drlight

3. **Import on drlight**:
   ```bash
   sudo zpool import data_pool
   sudo zfs mount -a
   ```

## Security

- **Encryption**: All data is encrypted with AES-256
- **Key Management**: Passphrase-based (stored in memory only)
- **Access Control**: Requires sudo for pool operations

## Monitoring

- **Health Checks**: `task zfs:health`
- **Capacity**: `task zfs:status`
- **Snapshots**: `zfs list -t snapshot`

## Troubleshooting

### Pool won't import
```bash
sudo zpool import -f data_pool  # Force import
```

### Forgotten encryption key
- Data recovery requires passphrase
- Consider key escrow for critical data

### Drive failure
- Mirror configuration allows single drive failure
- Replace failed drive: `sudo zpool replace data_pool /dev/failed_drive /dev/new_drive`
```

**Step 2: Update main README.md**

Add to the "🛠️ Development" section:

```markdown
### ZFS Storage

External hard drives with ZFS are configured for MegamanX:

```bash
# Setup external drives
task zfs:setup

# Check status
task zfs:status

# Migrate to Linux
task zfs:migrate
```

See [docs/zfs-setup.md](docs/zfs-setup.md) for detailed instructions.
```

**Step 3: Commit**

```bash
git add docs/ README.md
git commit -m "docs: add ZFS setup documentation"
```

### Task 8: Final validation and testing

**Files:**
- Test all configurations

**Step 1: Test Nix configuration**

Run: `nix flake check`
Expected: All configurations validate successfully

**Step 2: Test bundle configuration**

Run: `nix-instantiate --eval --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; in (import ./bundles.nix { inherit pkgs lib; }).roles.zfs'`
Expected: ZFS bundle configuration is valid

**Step 3: Test task availability**

Run: `task --list | grep zfs`
Expected: All ZFS tasks are listed

**Step 4: Test module syntax**

Run: `nix-instantiate --eval --expr 'let pkgs = import <nixpkgs> {}; lib = pkgs.lib; in (import ./modules/common/zfs.nix { config = {}; inherit lib pkgs; })'`
Expected: ZFS module syntax is valid

**Step 5: Run full test suite**

Run: `task test:full`
Expected: All tests pass

**Step 6: Final commit**

```bash
git add .
git commit -m "feat: complete ZFS external drives setup for MegamanX

- Add ZFS module with encryption and snapshots
- Configure production-grade features (compression, monitoring)
- Create setup and migration scripts
- Add comprehensive task management
- Include detailed documentation

Setup: task zfs:setup
Status: task zfs:status
Migration: task zfs:migrate
```

---

## Usage Instructions

### On MegamanX (macOS)

1. **Apply configuration**:
   ```bash
   darwin-rebuild switch
   ```

2. **Connect external USB-C drives**

3. **Run setup**:
   ```bash
   task zfs:setup
   ```

4. **Monitor status**:
   ```bash
   task zfs:status
   task zfs:health
   ```

### Migration to drlight (Linux)

1. **Prepare drives**:
   ```bash
   task zfs:migrate
   ```

2. **Move drives physically**

3. **Import on drlight**:
   ```bash
   sudo zpool import data_pool
   sudo zfs mount -a
   ```

The setup provides encrypted, compressed storage with automatic snapshots and monitoring, ready for production use.