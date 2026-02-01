#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration - override with environment variables
POOL_NAME="${ZFS_POOL_NAME:-data_pool}"
MOUNTPOINT="${ZFS_MOUNTPOINT:-/Volumes/data_pool}"
SNAPSHOT_PREFIX="${ZFS_SNAPSHOT_PREFIX:-auto}"
COMPRESSION_ALGORITHM="${ZFS_COMPRESSION_ALGORITHM:-lz4}"
ENCRYPTION_ALGORITHM="${ZFS_ENCRYPTION_ALGORITHM:-aes-256-gcm}"

# Function to check if running on macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS only"
        exit 1
    fi
    log_success "macOS detected"
}

# Function to check if OpenZFS is installed
check_openzfs() {
    if ! command -v zpool >/dev/null 2>&1; then
        log_error "OpenZFS is not installed"
        log_info "Please install OpenZFS first:"
        log_info "  brew install openzfs"
        log_info "Then follow the setup instructions at:"
        log_info "  https://openzfs.github.io/openzfs-docs/Getting%20Started/macOS/index.html"
        exit 1
    fi
    log_success "OpenZFS is installed"
}

# Function to list available disks
list_disks() {
    log_info "Available external disks:"
    diskutil list external | grep -E "^/dev/disk" | awk '{print $1}' | while read disk; do
        echo "  $disk - $(diskutil info "$disk" | grep "Device / Media Name" | sed 's/.*Device \/ Media Name: *//')"
    done
}

# Function to sanitize and validate disk input
sanitize_disk_input() {
    local input="$1"
    # Remove any dangerous characters and ensure proper format
    if [[ ! "$input" =~ ^/dev/disk[0-9]+$ ]]; then
        log_error "Invalid disk format: $input"
        log_error "Disk path must be in format: /dev/diskX (where X is a number)"
        exit 1
    fi
    echo "$input"
}

# Function to validate disk exists
validate_disk() {
    local disk="$1"
    disk=$(sanitize_disk_input "$disk")
    
    if [[ ! -b "$disk" ]]; then
        log_error "Disk $disk does not exist or is not a block device"
        list_disks
        exit 1
    fi
    
    # Check if it's an external disk
    if ! diskutil info "$disk" | grep -q "External"; then
        log_warning "$disk doesn't appear to be an external disk"
        log_warning "Please make sure you selected the correct disk"
        exit 1
    fi
    
    # Additional security checks
    if [[ "$disk" == "/dev/disk0" || "$disk" == "/dev/disk1" ]]; then
        log_error "CRITICAL: $disk appears to be a system disk"
        log_error "This script only works with external disks"
        exit 1
    fi
    
    echo "$disk"
}

# Function to get user confirmation with device details
get_confirmation() {
    local message="$1"
    local disk1="$2"
    local disk2="$3"
    
    echo
    log_warning "$message"
    echo
    log_info "DEVICE DETAILS:"
    echo "================================"
    
    # Show detailed disk information
    echo "Disk 1: $disk1"
    diskutil info "$disk1" | grep -E "(Device Node|Device / Media Name|Total Size|Protocol|Internal|External|Removable Media)" | while IFS=: read -r key value; do
        printf "  %-20s: %s\n" "$key" "$(echo "$value" | sed 's/^[[:space:]]*//')"
    done
    echo
    
    echo "Disk 2: $disk2"
    diskutil info "$disk2" | grep -E "(Device Node|Device / Media Name|Total Size|Protocol|Internal|External|Removable Media)" | while IFS=: read -r key value; do
        printf "  %-20s: %s\n" "$key" "$(echo "$value" | sed 's/^[[:space:]]*//')"
    done
    echo "================================"
    echo
    
    log_warning "This operation will COMPLETELY ERASE both disks shown above"
    log_warning "Verify the disk details carefully before proceeding"
    echo
    
    read -p "Type 'ERASE' to confirm complete data destruction: " confirmation
    
    if [[ "$confirmation" != "ERASE" ]]; then
        log_error "Operation cancelled by user"
        exit 1
    fi
}

# Function to check sudo privileges
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges"
        log_info "Please run with sudo: sudo $0 $@"
        exit 1
    fi
}

# Function to validate encryption status
validate_encryption_support() {
    log_info "Validating encryption support..."
    
    # Check if encryption is supported
    if ! zpool list | head -1 | grep -q "FEATURES"; then
        log_error "ZFS encryption features not available"
        log_info "Please ensure you're using a compatible ZFS version"
        exit 1
    fi
    
    log_success "Encryption support validated"
}

# Function to create ZFS pool
create_pool() {
    local disk1="$1"
    local disk2="$2"
    
    check_sudo
    validate_encryption_support
    
    log_info "Creating ZFS pool '$POOL_NAME' with encryption and compression..."
    
    # Create encrypted pool with mirror
    echo "Creating ZFS pool. You will be prompted to set a passphrase."
    echo "This passphrase will be required to unlock the pool on reboot."
    echo
    
    sudo zpool create \
        -o ashift=12 \
        -O compression="$COMPRESSION_ALGORITHM" \
        -O encryption="$ENCRYPTION_ALGORITHM" \
        -O keyformat=passphrase \
        -O keylocation=prompt \
        -O mountpoint="$MOUNTPOINT" \
        "$POOL_NAME" \
        mirror "$disk1" "$disk2"
    
    log_success "ZFS pool '$POOL_NAME' created successfully"
}

# Function to create datasets
create_datasets() {
    log_info "Creating datasets..."
    
    # Create main datasets with specific settings
    sudo zfs create -o mountpoint="$MOUNTPOINT/documents" "$POOL_NAME/documents"
    sudo zfs create -o mountpoint="$MOUNTPOINT/media" "$POOL_NAME/media"
    sudo zfs create -o mountpoint="$MOUNTPOINT/archives" "$POOL_NAME/archives"
    
    # Create media sub-datasets
    sudo zfs create "$POOL_NAME/media/photos"
    sudo zfs create "$POOL_NAME/media/videos"
    sudo zfs create "$POOL_NAME/media/music"
    
    # Set specific compression for different data types
    sudo zfs set compression=lz4 "$POOL_NAME/documents"
    sudo zfs set compression=gzip-6 "$POOL_NAME/archives"  # Better compression for archives
    
    log_success "Datasets created successfully"
}

# Function to validate mountpoint and create secure snapshot scripts
setup_snapshots() {
    log_info "Setting up automatic snapshot configuration..."
    
    # Validate mountpoint exists and is secure
    if [[ ! -d "$MOUNTPOINT" ]]; then
        log_error "Mountpoint $MOUNTPOINT does not exist"
        exit 1
    fi
    
    # Check mountpoint permissions
    local mount_perms=$(stat -f "%Lp" "$MOUNTPOINT")
    if [[ "$mount_perms" != "755" && "$mount_perms" != "700" ]]; then
        log_warning "Mountpoint has unusual permissions: $mount_perms"
        log_info "Setting secure permissions (755)"
        chmod 755 "$MOUNTPOINT"
    fi
    
    # Create snapshot retention script with secure permissions
    local cleanup_script="$MOUNTPOINT/.snapshot-cleanup.sh"
    cat > "$cleanup_script" << 'EOF'
#!/bin/bash
POOL_NAME="data_pool"
SNAPSHOT_PREFIX="auto"
MAX_DAILY=7
MAX_WEEKLY=4
MAX_MONTHLY=12

# Function to delete old snapshots
cleanup_snapshots() {
    local dataset="$1"
    local pattern="$2"
    local max_count="$3"
    
    local count=$(zfs list -t snapshot -o name "$dataset" | grep "$pattern" | wc -l)
    if [[ $count -gt $max_count ]]; then
        local to_delete=$((count - max_count))
        zfs list -t snapshot -o name "$dataset" | grep "$pattern" | head -n "$to_delete" | while read snapshot; do
            echo "Deleting old snapshot: $snapshot"
            zfs destroy "$snapshot"
        done
    fi
}

# Cleanup old snapshots for all datasets
for dataset in $(zfs list -o name -r data_pool | grep -v "^data_pool$"); do
    echo "Cleaning up snapshots for $dataset"
    cleanup_snapshots "$dataset" "$SNAPSHOT_PREFIX-daily" "$MAX_DAILY"
    cleanup_snapshots "$dataset" "$SNAPSHOT_PREFIX-weekly" "$MAX_WEEKLY"
    cleanup_snapshots "$dataset" "$SNAPSHOT_PREFIX-monthly" "$MAX_MONTHLY"
done
EOF
    
    chmod 750 "$cleanup_script"
    chown "$(whoami):staff" "$cleanup_script" 2>/dev/null || true
    
    # Create daily snapshot script with secure permissions
    local daily_script="$MOUNTPOINT/.snapshot-daily.sh"
    cat > "$daily_script" << 'EOF'
#!/bin/bash
POOL_NAME="data_pool"
SNAPSHOT_PREFIX="auto"
DATE=$(date +%Y-%m-%d)

for dataset in $(zfs list -o name -r data_pool); do
    echo "Creating daily snapshot for $dataset"
    zfs snapshot "$dataset@$SNAPSHOT_PREFIX-daily-$DATE"
done
EOF
    
    chmod 750 "$daily_script"
    chown "$(whoami):staff" "$daily_script" 2>/dev/null || true
    
    log_success "Snapshot scripts created in $MOUNTPOINT with secure permissions"
    log_info "To setup automatic snapshots, add to your crontab:"
    log_info "  0 2 * * * $MOUNTPOINT/.snapshot-daily.sh"
    log_info "  0 3 * * 0 $MOUNTPOINT/.snapshot-cleanup.sh"
}

# Function to create initial snapshot
create_initial_snapshot() {
    log_info "Creating initial snapshot..."
    local snapshot_name="$SNAPSHOT_PREFIX-initial-$(date +%Y-%m-%d-%H%M%S)"
    
    for dataset in $(sudo zfs list -o name -r "$POOL_NAME"); do
        sudo zfs snapshot "$dataset@$snapshot_name"
    done
    
    log_success "Initial snapshot '$snapshot_name' created"
}

# Function to show final status
show_status() {
    echo
    log_success "ZFS pool setup complete!"
    echo
    zpool status "$POOL_NAME"
    echo
    zfs list -r "$POOL_NAME"
    echo
    log_info "Pool information:"
    log_info "  Pool name: $POOL_NAME"
    log_info "  Mount point: $MOUNTPOINT"
    log_info "  Encryption: $ENCRYPTION_ALGORITHM"
    log_info "  Compression: $COMPRESSION_ALGORITHM"
    log_info "  Configuration: mirror"
    echo
    log_warning "Important notes:"
    log_warning "1. Save your encryption passphrase in a secure location"
    log_warning "2. Pool will need to be unlocked after reboots with: zpool mount $POOL_NAME"
    log_warning "3. Use 'zfs list -t snapshot' to view snapshots"
    log_warning "4. Use 'zfs destroy <snapshot>' to remove snapshots"
}

# Main execution
main() {
    log_info "Starting ZFS pool setup for macOS..."
    
    # Check prerequisites
    check_macos
    check_openzfs
    
    echo
    log_info "This script will create an encrypted ZFS pool with mirror configuration"
    log_info "This will completely erase the selected disks"
    echo
    
    # Show available disks
    list_disks
    echo
    
    # Get first disk
    read -p "Enter first disk (e.g., /dev/disk3): " disk1
    disk1=$(validate_disk "$disk1")
    
    # Get second disk
    read -p "Enter second disk (e.g., /dev/disk4): " disk2
    disk2=$(validate_disk "$disk2")
    
    # Show disk information
    echo
    log_info "Selected disks:"
    diskutil info "$disk1" | grep -E "(Device Node|Device / Media Name|Total Size)"
    diskutil info "$disk2" | grep -E "(Device Node|Device / Media Name|Total Size)"
    echo
    
    # Get final confirmation with device details
    get_confirmation "This will COMPLETELY ERASE all data on both disks" "$disk1" "$disk2"
    
    # Create pool
    create_pool "$disk1" "$disk2"
    
    # Create datasets
    create_datasets
    
    # Setup snapshots
    setup_snapshots
    
    # Create initial snapshot
    create_initial_snapshot
    
    # Show final status
    show_status
}

# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi