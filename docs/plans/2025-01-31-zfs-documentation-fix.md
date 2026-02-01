# ZFS Documentation Alignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Align ZFS documentation with actual implementation by fixing task names, pool names, dataset structure, and platform limitations.

**Architecture:** Review actual Taskfile.yml and scripts, then update docs/zfs-setup.md and README.md to reflect reality.

**Tech Stack:** Nix flake configuration, ZFS on macOS, Go tasks, Bash scripts

## Analysis Task

### Task 1: Analyze Current Implementation

**Files:**
- Read: `Taskfile.yml` (zfs tasks section)
- Read: `scripts/zfs-setup.sh`
- Read: `scripts/zfs-migrate.sh`
- Read: `docs/zfs-setup.md`
- Read: `README.md` (ZFS section)

**Step 1: Extract actual task names and functionality**

From Taskfile.yml:
- `zfs:setup` - Interactive setup script (NOT setup-pool with args)
- `zfs:status` - Shows pool and dataset status
- `zfs:health` - System health check
- `zfs:migrate` - Migration preparation
- `zfs:snapshot` - Manual snapshot creation
- `zfs:scrub` - Data integrity scrub

From scripts:
- Default pool name: `backup` (NOT `storage` or `data_pool`)
- Dataset structure: `documents/`, `media/`, `archives/` (NOT `backup/`, `projects/`, `temp/`)
- Platform: macOS only (MegamanX) with OpenZFS via brew
- Encryption: Passphrase-based (NOT system-managed keys)

**Step 2: Document discrepancies**

Critical issues found:
1. Task names: `zfs:setup-pool` → `zfs:setup`
2. Non-existent tasks: `create-datasets`, `mount-all`, `import`, `export`, `snapshot-cleanup`
3. Pool name: `storage` → `backup`
4. Dataset structure mismatch
5. Platform limitations undocumented (macOS-only)
6. Security model wrong (passphrase vs system keys)

## Documentation Fixes

### Task 2: Fix docs/zfs-setup.md Task Names

**Files:**
- Modify: `docs/zfs-setup.md:72-93` (Quick Setup section)
- Modify: `docs/zfs-setup.md:80-112` (Available Tasks table)
- Modify: `docs/zfs-setup.md:296-300` (Best Practices section)

**Step 1: Update Quick Setup section**

Replace lines 72-78:
```bash
# OLD (remove these lines):
task zfs:setup-pool /dev/sda /dev/sdb
task zfs:status

# NEW (add these lines):
task zfs:setup
# Follow prompts to select disks interactively
task zfs:status
```

**Step 2: Update Available Tasks table**

Replace entire table (lines 82-93):
```markdown
| Task | Description |
|------|-------------|
| `task zfs:setup` | Interactive setup of external drives with disk selection |
| `task zfs:status` | Show pool health, capacity, and dataset status |
| `task zfs:health` | Check ZFS system health and error status |
| `task zfs:snapshot` | Create manual timestamped snapshot |
| `task zfs:scrub` | Start data integrity scrub |
| `task zfs:migrate` | Prepare pool for migration to Linux system |
```

**Step 3: Update task descriptions**

Replace task descriptions section (lines 94-112):
```markdown
#### Pool Management
- **`task zfs:setup`**: Interactive setup script that prompts for disk selection. Creates encrypted mirror pool with optimal settings. Erases existing data on selected devices.
- **`task zfs:migrate`**: Exports pool and prepares for migration to Linux (drlight) system.

#### Monitoring
- **`task zfs:status`**: Comprehensive pool health, capacity, usage, and dataset listing.
- **`task zfs:health`**: Quick system health check and error status.

#### Maintenance
- **`task zfs:snapshot`**: Creates timestamped manual snapshot for backup purposes.
- **`task zfs:scrub`**: Initiates full data integrity check (recommended monthly).
```

**Step 4: Update Best Practices section**

Replace lines 296-300:
```markdown
### Regular Maintenance
- **Weekly scrubs**: `task zfs:scrub` or automated schedule
- **Manual snapshots**: `task zfs:snapshot` for important changes
- **Health monitoring**: Check `task zfs:status` and `task zfs:health` weekly
- **Backup verification**: Test restore procedures quarterly
```

### Task 3: Fix Pool Name and Dataset Structure

**Files:**
- Modify: `docs/zfs-setup.md:6-36` (Overview and Dataset Structure)
- Modify: `docs/zfs-setup.md:46-78` (Quick Setup references)
- Modify: `docs/zfs-setup.md:113-160` (Migration section)

**Step 1: Update Pool Configuration**

Replace lines 7-14:
```markdown
**Pool Configuration:**
- **Pool Name**: `backup`
- **Configuration**: Mirror (RAID1) setup for redundancy
- **Encryption**: AES-256-GCM with passphrase-based native ZFS encryption
- **Compression**: LZ4 for documents, gzip-6 for archives
- **Deduplication**: Disabled for external drive performance
- **Snapshots**: Manual and automatic with intelligent retention policies
- **Auto-scrub**: Weekly data integrity checks recommended
```

**Step 2: Update Dataset Structure**

Replace lines 16-36:
```markdown
### Dataset Structure

```
backup/
├── documents/                 # Documents and text files (LZ4 compression)
│   └── (user documents)
├── media/                     # Media files and collections
│   ├── photos/               # Photo library
│   ├── videos/               # Video collection
│   └── music/                # Music library
└── archives/                  # Compressed archives (gzip-6 compression)
    └── (archived projects, installers)
```

**Step 3: Update migration references**

Replace lines 140-141:
```bash
# On drlight (after manual setup), import the existing pool
sudo zpool import backup
# Verify pool status
task zfs:status  # Note: This task only works on macOS
```

### Task 4: Add Platform-Specific Limitations

**Files:**
- Modify: `docs/zfs-setup.md:38-60` (Prerequisites and Setup)
- Modify: `docs/zfs-setup.md:162-179` (Security section)
- Add: Platform limitation notice at top

**Step 1: Add platform limitation notice**

Add after line 5 (after overview):
```markdown
> **Platform Notice**: This ZFS configuration is currently designed for macOS (MegamanX) only. Linux (drlight) support requires manual ZFS setup and different package management.
```

**Step 2: Update Prerequisites**

Replace lines 41-52:
```markdown
### Prerequisites

1. **macOS system** (MegamanX target):
   - OpenZFS installed via Homebrew: `brew install openzfs`
   - ZFS kernel extensions loaded: `sudo kextload -b org.openzfs.zfs`

2. **External drives** connected and identified:
   ```bash
   # List available disks (exclude ZFS members)
   diskutil list external | grep -E "(external, virtual|synthetic|FDisk_partition_scheme)"
   ```

3. **Repository scripts** available:
   ```bash
   # Verify setup script exists and is executable
   test -f ./scripts/zfs-setup.sh && test -x ./scripts/zfs-setup.sh
   ```
```

**Step 3: Update Initial Setup**

Replace lines 55-78:
```markdown
### Initial Setup

1. **Ensure OpenZFS is installed** (macOS only):
   ```bash
   brew install openzfs
   # Load kernel extensions
   sudo kextload -b org.openzfs.zfs
   ```

2. **Connect external drives** and verify detection:
   ```bash
   # List external drives
   diskutil list external
   # Note device identifiers (e.g., disk4, disk5)
   ```

3. **Run interactive ZFS pool setup**:
   ```bash
   task zfs:setup
   # Follow prompts to select disks interactively
   # Script will guide you through disk selection
   ```

4. **Verify pool status**:
   ```bash
   task zfs:status
   ```
```

### Task 5: Fix Security Documentation

**Files:**
- Modify: `docs/zfs-setup.md:162-179` (Security section)

**Step 1: Update Encryption section**

Replace lines 164-179:
```markdown
### Encryption
- **Algorithm**: AES-256-GCM (hardware accelerated when available)
- **Key Management**: Passphrase-based native ZFS encryption
- **Key Source**: User-provided passphrase entered during setup
- **Key Storage**: No permanent key storage - passphrase required on pool import
- **Protection**: Data encrypted at rest, unlocked with passphrase when mounted
- **Recovery**: Passphrase must be remembered - no recovery mechanism available

> **Important**: Store your encryption passphrase securely (e.g., 1Password). Loss of passphrase means permanent data loss.
```

**Step 2: Add 1Password integration note**

Add after Security section:
```markdown
### 1Password Integration

For this repository's security model:
- Store ZFS pool passphrase in 1Password as "ZFS Pool Passphrase"
- Use `op run` for automated operations requiring passphrase access
- Scripts integrate with 1Password for secure credential handling
```

### Task 6: Update README.md ZFS Section

**Files:**
- Modify: `README.md:121-141` (ZFS section)

**Step 1: Fix task names and descriptions**

Replace lines 123-132:
```markdown
```bash
# Quick ZFS commands (macOS only)
task zfs:setup               # Interactive setup with disk selection
task zfs:status              # Show pool health and dataset status
task zfs:health              # Check system health
task zfs:snapshot            # Create manual backup snapshot
task zfs:scrub               # Start data integrity scrub
task zfs:migrate             # Prepare for migration to Linux

# Full documentation
cat docs/zfs-setup.md
```
```

**Step 2: Update features description**

Replace lines 134-141:
```markdown
**Features:**
- **Encrypted Storage**: AES-256-GCM encryption with passphrase protection
- **Redundancy**: Mirror configuration for data protection
- **Manual Snapshots**: On-demand snapshots with automatic cleanup scripts
- **macOS Optimized**: Designed for macOS with OpenZFS via Homebrew
- **Performance Monitoring**: Real-time I/O statistics and health monitoring
- **Migration Ready**: Prepared for migration to Linux (drlight) systems

> **Platform**: Currently macOS-only. Linux support requires manual setup.

See [ZFS Setup Guide](docs/zfs-setup.md) for complete documentation.
```

## Testing and Validation

### Task 7: Validate Documentation Changes

**Files:**
- Read: `docs/zfs-setup.md` (updated sections)
- Read: `README.md` (updated ZFS section)
- Run: Documentation validation

**Step 1: Verify task name consistency**

Check all documentation references:
```bash
# Search for old task names
grep -r "zfs:setup-pool\|zfs:create-datasets\|zfs:mount-all\|zfs:import\|zfs:export\|zfs:snapshot-cleanup" docs/ README.md
# Should return no matches
```

**Step 2: Verify pool name consistency**

Check pool name references:
```bash
# Verify pool name is "backup" everywhere
grep -r "storage\|data_pool" docs/ README.md
# Should only find non-ZFS storage references
```

**Step 3: Verify platform limitations documented**

Check macOS-only notice:
```bash
# Verify platform limitation is documented
grep -r "macOS only\|macOS-only\|Platform Notice" docs/ README.md
# Should find at least 3 matches
```

## Final Commit

### Task 8: Commit Documentation Fixes

**Files:**
- Modify: `docs/zfs-setup.md`
- Modify: `README.md`

**Step 1: Review all changes**

```bash
git diff docs/zfs-setup.md README.md
```

**Step 2: Stage and commit**

```bash
git add docs/zfs-setup.md README.md
git commit -m "fix: align ZFS documentation with actual implementation

- Fix task names to match Taskfile.yml (setup, status, health, etc.)
- Remove references to non-existent tasks (setup-pool, create-datasets, etc.)
- Standardize pool name to 'backup' matching scripts
- Update dataset structure to match actual script output
- Add macOS-only platform limitations notice
- Fix security model to reflect passphrase-based encryption
- Update README.md ZFS section with correct task names
- Add 1Password integration notes for repository security model"
```

**Step 3: Verify changes**

```bash
git log -1 --stat
```

## Success Criteria

Documentation is fixed when:
- [ ] All task names in docs match Taskfile.yml exactly
- [ ] Pool name consistently documented as "backup"
- [ ] Dataset structure matches script output
- [ ] Platform limitations clearly documented
- [ ] Security model reflects passphrase-based encryption
- [ ] README.md ZFS section matches detailed docs
- [ ] No references to non-existent tasks remain
- [ ] Changes committed with proper message