# ZFS External Drives Setup Guide

## Overview

Comprehensive ZFS external storage solution with automated management, encryption, and backup capabilities.

**Platform Support:** Currently macOS-only (MegamanX) with Linux compatibility planned.

**Pool Configuration:**
- **Pool Name**: `data_pool`
- **Configuration**: Mirror (RAID1) setup for redundancy
- **Encryption**: AES-256-GCM with native ZFS encryption
- **Compression**: LZ4 for performance/space balance
- **Deduplication**: Disabled for external drive performance
- **Snapshots**: Automatic with intelligent retention policies
- **Auto-scrub**: Weekly data integrity checks

### Dataset Structure

```
data_pool/
├── documents/                # Documents and files
├── media/                    # Media files (photos, videos, music)
│   ├── photos/               # Photo library
│   ├── videos/               # Video collection
│   └── music/                # Music library
└── archives/                 # Long-term archive storage
```

## Quick Setup

### Prerequisites

1. **macOS system** (currently macOS-only, MegamanX)
2. **OpenZFS installed** on target system:
   ```bash
   brew install openzfs
   ```

3. **External drives** connected and identified:
   ```bash
   diskutil list external
   ```

### Initial Setup

1. **Apply system configuration** on macOS:
   ```bash
   darwin-rebuild switch --flake ./
   ```

2. **Connect external drives** and verify detection:
   ```bash
   # List available external disks
   diskutil list external
   # Identify target drives (e.g., /dev/disk3, /dev/disk4)
   ```

3. **Run initial ZFS pool setup**:
   ```bash
   task zfs:setup
   ```

4. **Verify pool status**:
   ```bash
   task zfs:status
   ```

## Available Tasks

| Task | Description |
|------|-------------|
| `task zfs:setup` | Create initial ZFS pool with guided setup |
| `task zfs:status` | Show pool health, capacity, and status |
| `task zfs:health` | Check ZFS system health |
| `task zfs:snapshot` | Create manual snapshot |
| `task zfs:scrub` | Start data integrity scrub |
| `task zfs:migrate` | Prepare pool for migration to Linux |

### Task Descriptions

#### Pool Management
- **`task zfs:setup`**: Interactive setup that creates encrypted mirror pool with optimal settings. Erases existing data on devices.
- **`task zfs:migrate`**: Prepares pool for migration to Linux by exporting safely.

#### Maintenance
- **`task zfs:snapshot`**: Creates timestamped manual snapshot.
- **`task zfs:scrub`**: Initiates full data integrity check (recommended monthly).

#### Monitoring
- **`task zfs:status`**: Comprehensive pool health, capacity, usage, and I/O statistics.
- **`task zfs:health`**: Quick health check of ZFS system.

## Migration to Linux (drlight)

### Current State
- macOS (MegamanX): ZFS pool in mirror configuration (2x4TB)
- Datasets for documents, media, archives
- Working snapshot and backup system

### Migration Steps

1. **Prepare macOS system**:
   ```bash
   # Export pool for migration
   task zfs:migrate
   ```

2. **Physical drive transfer**:
   - Safely disconnect external ZFS drives from macOS
   - Connect drives to Linux system (drlight)

3. **Install ZFS on Linux**:
   ```bash
   # Ubuntu/Debian
   sudo apt install zfsutils-linux
   # RHEL/CentOS
   sudo yum install zfs
   ```

4. **Import existing pool**:
    ```bash
    # On Linux, import the existing pool
    sudo zpool import data_pool
    # You'll be prompted for the encryption passphrase
    # Verify pool status
    sudo zpool status data_pool
    ```

5. **Verify dataset access**:
    ```bash
    # List datasets
    sudo zfs list -r data_pool
    # Check data integrity
    ls -la /mnt/data_pool/
    ```

6. **Set up mount points**:
    ```bash
    # Create mountpoints if needed
    sudo mkdir -p /mnt/data_pool
    sudo zfs set mountpoint=/mnt/data_pool data_pool
    ```

### Considerations
- **Data continuity**: No data migration needed - pool imports with all data intact
- **Performance**: Potential performance improvements on Linux host
- **Integration**: Better integration with NixOS ecosystem
- **Monitoring**: Enhanced monitoring capabilities on Linux
- **Encryption**: Passphrase will be required during import to Linux and after system reboots

## Operational Requirements

### ⚠️ Critical: Passphrase Requirement After Reboot

**WARNING:** Your ZFS pool uses encryption and requires manual intervention after system restarts.

- **After every reboot**, the pool will be locked and you must provide the encryption passphrase
- To unlock and mount the pool after reboot:
  ```bash
  # Import the pool (will prompt for passphrase)
  sudo zpool import data_pool
  
  # Or if already imported but locked
  sudo zfs mount data_pool
  ```

- **Store your passphrase securely** - you cannot access data without it
- Consider setting up automatic mount scripts if frequent reboots are expected
- For unattended reboots, consider using key files instead of passphrase (reduces security)

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
sudo zpool import -f data_pool
# Check for missing devices
sudo zpool import -c /etc/zfs/zpool.cache data_pool
```

#### Dataset Won't Mount
```bash
# Check mount status
zfs get mounted data_pool/documents
# Mount manually
sudo zfs mount data_pool/documents
# Check mountpoint
zfs get mountpoint data_pool/documents
```

#### Performance Issues
```bash
# Check I/O statistics
zpool iostat -v 1
# Check ARC statistics
arcstat
# Check compression ratio
zfs get compressratio data_pool
```

#### Space Issues
```bash
# Check space usage
zfs list -o space
# Find large files
sudo find /mnt/data_pool -type f -size +10G -ls
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
    sudo zpool replace data_pool /dev/sda /dev/sdc
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
    sudo zpool scrub data_pool
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
- **Capacity monitoring**: Check `task zfs:status` weekly
- **Health checks**: Run `task zfs:health` monthly
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