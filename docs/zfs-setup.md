# ZFS External Drives Setup Guide

## Overview

Comprehensive ZFS external storage solution with automated management, encryption, and backup capabilities.

**Pool Configuration:**
- **Pool Name**: `storage`
- **Configuration**: Mirror (RAID1) setup for redundancy
- **Encryption**: AES-256-GCM with native ZFS encryption
- **Compression**: LZ4 for performance/space balance
- **Deduplication**: Disabled for external drive performance
- **Snapshots**: Automatic with intelligent retention policies
- **Auto-scrub**: Weekly data integrity checks

### Dataset Structure

```
storage/
├── backup/                    # Time Machine / system backups
│   ├── macbook-pro/          # MacBook Pro backups
│   └── drlight/              # drlight NixOS backups
├── media/                    # Media files (photos, videos, music)
│   ├── photos/               # Photo library
│   ├── videos/               # Video collection
│   └── music/                # Music library
├── projects/                 # Project work and development
│   ├── nix-config/           # Nix configuration repository
│   └── active/               # Active project work
├── archive/                  # Long-term archive storage
│   ├── documents/            # Document archive
│   └── software/             # Software installers and old versions
└── temp/                     # Temporary scratch space
    ├── downloads/            # Downloaded files
    └── working/              # Active working files
```

## Quick Setup

### Prerequisites

1. **ZFS tools installed** on target system:
   ```bash
   # Available in system configuration
   nix-shell -p zfs
   ```

2. **External drives** connected and identified:
   ```bash
   lsblk -f | grep -v zfs
   ```

### Initial Setup

1. **Build and apply system configuration**:
   ```bash
   task build:linux:drlight
   # Deploy to drlight system
   darwin-rebuild switch  # macOS
   sudo nixos-rebuild switch  # NixOS
   ```

2. **Connect external drives** and verify detection:
   ```bash
   # List available disks
   lsblk -f
   # Identify target drives (e.g., /dev/sda, /dev/sdb)
   ```

3. **Run initial ZFS pool setup**:
   ```bash
   task zfs:setup-pool /dev/sda /dev/sdb
   ```

4. **Verify pool status**:
   ```bash
   task zfs:status
   ```

## Available Tasks

| Task | Description |
|------|-------------|
| `task zfs:setup-pool <device1> <device2>` | Create initial ZFS pool with specified devices |
| `task zfs:create-datasets` | Create initial dataset structure |
| `task zfs:status` | Show pool health, capacity, and status |
| `task zfs:mount-all` | Mount all datasets on system |
| `task zfs:backup` | Create manual backup snapshot |
| `task zfs:snapshot-cleanup` | Clean up old snapshots per retention policy |
| `task zfs:scrub` | Start data integrity scrub |
| `task zfs:import` | Import existing ZFS pool |
| `task zfs:export` | Safely export ZFS pool for transport |

### Task Descriptions

#### Pool Management
- **`task zfs:setup-pool <device1> <device2>`**: Creates encrypted mirror pool with optimal settings. Erases existing data on devices.
- **`task zfs:import`**: Imports existing pool when drives reconnected or system rebooted.
- **`task zfs:export`**: Safely prepares pool for transport or system maintenance.

#### Dataset Operations
- **`task zfs:create-datasets`**: Creates the full dataset hierarchy with appropriate mount points and properties.
- **`task zfs:mount-all`**: Mounts all datasets to their configured mount points.

#### Maintenance
- **`task zfs:backup`**: Creates timestamped backup snapshot with description.
- **`task zfs:snapshot-cleanup`**: Removes snapshots exceeding retention policy (30d daily, 12w weekly, 12m monthly).
- **`task zfs:scrub`**: Initiates full data integrity check (recommended monthly).

#### Monitoring
- **`task zfs:status`**: Comprehensive pool health, capacity, usage, and I/O statistics.

## Migration to drlight

### Current State
- MacBook Pro: ZFS pool in mirror configuration (2x4TB)
- Several datasets for backup, media, projects, archive
- Working snapshot and backup system

### Migration Steps

1. **Prepare drlight system**:
   ```bash
   # Ensure ZFS tools available
   task build:linux:drlight
   # Apply configuration to drlight
   sudo nixos-rebuild switch
   ```

2. **Physical drive transfer**:
   - Power down MacBook Pro
   - Physically move external ZFS drives to drlight
   - Connect drives to drlight system

3. **Import existing pool**:
   ```bash
   # On drlight, import the existing pool
   sudo zpool import storage
   # Verify pool status
   task zfs:status
   ```

4. **Verify dataset access**:
   ```bash
   # Mount all datasets
   task zfs:mount-all
   # Check data integrity
   ls -la /mnt/storage/
   ```

5. **Update backup scripts**:
   - Modify backup paths to reflect drlight system
   - Update cron jobs and automation
   - Test backup procedures

### Considerations
- **Data continuity**: No data migration needed - pool imports with all data intact
- **Performance**: Potential performance improvements on Linux host
- **Integration**: Better integration with NixOS ecosystem
- **Monitoring**: Enhanced monitoring capabilities on Linux

## Security

### Encryption
- **Algorithm**: AES-256-GCM (hardware accelerated when available)
- **Key Management**: Native ZFS encryption with system integration
- **Key Source**: System-managed key files in secure location
- **Protection**: Data encrypted at rest, transparent when mounted

### Access Control
- **Permissions**: Standard Unix file permissions on datasets
- **Mount Points**: Controlled access via mount point permissions
- **Network**: No network services expose ZFS data directly

### Backup Security
- **Snapshots**: Read-only copies preserve data integrity
- **Replication**: Encrypted replication when implemented
- **Key Rotation**: Supported for long-term security maintenance

## Monitoring

### Health Monitoring
- **Pool Health**: `zpool status` shows overall pool state
- **Device Status**: Individual drive health and error tracking
- **Data Integrity**: Automatic checksum detection and correction
- **Capacity**: Usage tracking and alerting at 80% threshold

### Performance Monitoring
- **I/O Statistics**: Detailed read/write performance metrics
- **Cache Performance**: ARC (Adaptive Replacement Cache) statistics
- **Compression Ratio**: Real-time compression effectiveness

### Automation
- **Email Alerts**: Configurable alerts for pool degradation
- **System Integration**: Nagios/Prometheus monitoring hooks
- **Log Monitoring**: Centralized logging for ZFS events

## Troubleshooting

### Common Issues

#### Pool Won't Import
```bash
# List available pools
sudo zpool import
# Force import if needed (careful!)
sudo zpool import -f storage
# Check for missing devices
sudo zpool import -c /etc/zfs/zpool.cache storage
```

#### Dataset Won't Mount
```bash
# Check mount status
zfs get mounted storage/backup
# Mount manually
sudo zfs mount storage/backup
# Check mountpoint
zfs get mountpoint storage/backup
```

#### Performance Issues
```bash
# Check I/O statistics
zpool iostat -v 1
# Check ARC statistics
arcstat
# Check compression ratio
zfs get compressratio storage
```

#### Space Issues
```bash
# Check space usage
zfs list -o space
# Find large files
sudo find /mnt/storage -type f -size +10G -ls
# Check snapshot usage
zfs list -t snapshot
```

### Recovery Procedures

#### Device Failure
1. **Identify failed device**:
   ```bash
   sudo zpool status -v
   ```

2. **Replace device**:
   ```bash
   sudo zpool replace storage /dev/sda /dev/sdc
   ```

3. **Monitor resilver**:
   ```bash
   watch sudo zpool status
   ```

#### Corruption Detection
1. **Check checksum errors**:
   ```bash
   sudo zpool status -v
   ```

2. **Scrub pool**:
   ```bash
   sudo zpool scrub storage
   ```

3. **Monitor repair progress**:
   ```bash
   watch sudo zpool status
   ```

### Getting Help

1. **Check system logs**:
   ```bash
   journalctl -u zfs
   dmesg | grep -i zfs
   ```

2. **ZFS documentation**:
   - OpenZFS documentation
   - Arch Wiki ZFS page
   - FreeBSD ZFS guide

3. **Community support**:
   - OpenZFS mailing list
   - Reddit r/zfs
   - Local Linux user groups

## Best Practices

### Regular Maintenance
- **Weekly scrubs**: `task zfs:scrub` or automated schedule
- **Snapshot cleanup**: `task zfs:snapshot-cleanup` monthly
- **Capacity monitoring**: Check `task zfs:status` weekly
- **Backup verification**: Test restore procedures quarterly

### Performance Optimization
- **Avoid overfilling**: Keep pool usage below 80%
- **Monitor fragmentation**: Check `zfs get fragmentation` periodically
- **Tune recordsize**: Adjust for specific workload patterns
- **Cache optimization**: Monitor ARC hit ratios

### Security Maintenance
- **Key rotation**: Consider annually for high-security environments
- **Access review**: Audit dataset permissions quarterly
- **Backup verification**: Test encryption key recovery procedures