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

# Function to check sudo privileges
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This operation requires root privileges"
        log_info "Please run with sudo: sudo $0 $@"
        exit 1
    fi
}

# Function to validate encrypted pool status
validate_encryption_status() {
    log_info "Validating encryption status..."
    
    # Check if pool is encrypted
    local encryption_status=$(sudo zfs get -H -o value encryption "$POOL_NAME" 2>/dev/null || echo "off")
    if [[ "$encryption_status" == "off" ]]; then
        log_warning "Pool '$POOL_NAME' is not encrypted"
    else
        log_success "Pool encryption status: $encryption_status"
        
        # Check if encryption key is loaded
        local key_status=$(sudo zfs get -H -o value keystatus "$POOL_NAME" 2>/dev/null || echo "unavailable")
        if [[ "$key_status" == "available" ]]; then
            log_success "Encryption key is loaded and available"
        else
            log_warning "Encryption key status: $key_status"
            log_warning "You may need to provide the encryption passphrase during import on Linux"
        fi
    fi
}

# Function to check if pool exists
check_pool_exists() {
    check_sudo
    
    if ! sudo zpool list "$POOL_NAME" >/dev/null 2>&1; then
        log_error "ZFS pool '$POOL_NAME' does not exist"
        log_info "Available pools:"
        sudo zpool list
        exit 1
    fi
    log_success "ZFS pool '$POOL_NAME' found"
    
    # Validate encryption status
    validate_encryption_status
}

# Function to show pool status
show_pool_status() {
    log_info "Current pool status:"
    sudo zpool status "$POOL_NAME"
    echo
    log_info "Pool datasets:"
    sudo zfs list -r "$POOL_NAME"
    echo
    
    # Show device information for migration verification
    log_info "Device information for migration:"
    sudo zpool list -v "$POOL_NAME" | grep -E "(mirror|disk)"
}

# Function to export pool safely
export_pool() {
    log_info "Exporting ZFS pool '$POOL_NAME' for migration..."
    
    # Check if any datasets are busy
    if sudo zfs list -r "$POOL_NAME" | grep -q "legacy"; then
        log_warning "Some datasets may have legacy mountpoints"
        log_warning "Make sure all datasets are unmounted before proceeding"
    fi
    
    # Check for active processes using the pool
    log_info "Checking for processes using the pool..."
    local active_processes=$(lsof +D "$(sudo zfs get -H -o value mountpoint "$POOL_NAME" 2>/dev/null || echo "/Volumes/$POOL_NAME")" 2>/dev/null | wc -l || echo "0")
    if [[ "$active_processes" -gt 0 ]]; then
        log_warning "Found $active_processes processes using the pool"
        log_warning "Files may be in use by running applications"
        echo
        lsof +D "$(sudo zfs get -H -o value mountpoint "$POOL_NAME" 2>/dev/null || echo "/Volumes/$POOL_NAME")" 2>/dev/null || true
        echo
    fi
    
    # Attempt to unmount the pool
    if ! sudo zpool export "$POOL_NAME"; then
        log_error "Failed to export pool '$POOL_NAME'"
        log_info "Possible reasons:"
        log_info "  1. Dataset is in use (files open)"
        log_info "  2. Mountpoint is busy"
        log_info "  3. Pool is in use by system"
        echo
        log_info "Try the following:"
        log_info "  1. Close all applications using files on the pool"
        log_info "  2. Unmount datasets manually: zfs unmount -a"
        log_info "  3. Force unmount: zpool export -f $POOL_NAME"
        exit 1
    fi
    
    log_success "ZFS pool '$POOL_NAME' exported successfully"
}

# Function to verify pool is exported
verify_export() {
    if zpool list "$POOL_NAME" >/dev/null 2>&1; then
        log_error "Pool '$POOL_NAME' is still listed - export may have failed"
        exit 1
    fi
    log_success "Pool '$POOL_NAME' is no longer listed - export verified"
}

# Function to provide Linux import instructions
show_linux_instructions() {
    echo
    log_success "Pool is ready for migration to Linux!"
    echo
    log_info "Steps to import on Linux:"
    echo
    echo "1. Connect the external drives to the Linux system"
    echo "2. Make sure ZFS is installed:"
    echo "   sudo apt install zfsutils-linux  # Ubuntu/Debian"
    echo "   sudo yum install zfs             # RHEL/CentOS"
    echo
    echo "3. Import the pool:"
    echo "   sudo zpool import data_pool"
    echo "   # You'll be prompted for the encryption passphrase"
    echo
    echo "4. Verify import:"
    echo "   sudo zpool status data_pool"
    echo "   sudo zfs list -r data_pool"
    echo
    echo "5. Create mountpoints if needed:"
    echo "   sudo mkdir -p /mnt/data_pool"
    echo "   sudo zfs set mountpoint=/mnt/data_pool data_pool"
    echo
    echo "6. Enable auto-mount on boot (optional):"
    echo "   sudo zpool set cachefile=/etc/zfs/zpool.cache data_pool"
    echo "   sudo systemctl enable zfs-import-cache"
    echo "   sudo systemctl enable zfs-mount"
    echo
    log_warning "Important notes:"
    log_warning "1. The pool uses mirror configuration (2 drives)"
    log_warning "2. Encryption is AES-256-GCM with passphrase"
    log_warning "3. Both drives must be connected for the mirror to work"
    log_warning "4. Keep the encryption passphrase safe!"
}

# Function to show rollback instructions
show_rollback_instructions() {
    echo
    log_info "If you need to rollback and use the pool on macOS again:"
    echo
    echo "1. Reconnect the drives to macOS"
    echo "2. Import the pool:"
    echo "   sudo zpool import data_pool"
    echo "   # You'll be prompted for the encryption passphrase"
    echo
    echo "3. The pool should mount automatically at /Volumes/data_pool"
    echo
    log_warning "Note: This should only be needed if the migration fails"
}

# Function to handle force export option
handle_force_export() {
    log_warning "Attempting force export..."
    
    # Try to unmount all datasets first
    log_info "Attempting to unmount all datasets..."
    sudo zfs unmount -a -r "$POOL_NAME" 2>/dev/null || true
    
    # Check for remaining open files
    log_info "Checking for remaining open files..."
    local mount_point=$(sudo zfs get -H -o value mountpoint "$POOL_NAME" 2>/dev/null || echo "/Volumes/$POOL_NAME")
    if [[ -d "$mount_point" ]]; then
        local open_files=$(lsof +D "$mount_point" 2>/dev/null || echo "")
        if [[ -n "$open_files" ]]; then
            log_warning "Found open files preventing export:"
            echo "$open_files"
            echo
            log_info "Processes that may need to be terminated:"
            echo "$open_files" | awk '{print $1}' | sort -u | sed 's/^/  /'
            echo
        fi
    fi
    
    # Force export with detailed error reporting
    log_info "Attempting force export..."
    if sudo zpool export -f "$POOL_NAME" 2>&1; then
        log_success "Force export successful"
        return 0
    else
        local export_error=$?
        log_error "Force export failed with exit code $export_error"
        log_info "Detailed analysis:"
        
        # Check pool health
        local pool_health=$(sudo zpool list -H -o health "$POOL_NAME" 2>/dev/null || echo "unknown")
        log_info "Pool health: $pool_health"
        
        # Check for I/O errors
        local error_count=$(sudo zpool status "$POOL_NAME" | grep -E "errors:" | awk '{sum+=$2} END {print sum+0}' || echo "0")
        if [[ "$error_count" -gt 0 ]]; then
            log_warning "Pool reports $error_count errors - this may prevent export"
        fi
        
        # Check if pool is in use by system
        if sudo zpool status "$POOL_NAME" | grep -q "state: ONLINE"; then
            log_info "Pool is online and healthy - export should be possible"
        fi
        
        log_info "Troubleshooting steps:"
        log_info "1. Close all applications using files on the pool"
        log_info "2. Terminate processes: kill -9 <PID> for processes shown above"
        log_info "3. Wait a few seconds and retry normal export"
        log_info "4. If all else fails, consider system restart before migration"
        
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting ZFS pool migration preparation..."
    
    # Check if pool exists
    check_pool_exists
    
    # Show current status
    show_pool_status
    
    echo
    log_warning "This will prepare the ZFS pool '$POOL_NAME' for migration to Linux"
    log_warning "The pool will be exported and will no longer be accessible on macOS"
    echo
    
    # Show detailed pool information for verification
    log_info "POOL MIGRATION DETAILS:"
    echo "================================"
    log_info "Pool Name: $POOL_NAME"
    log_info "Pool Health: $(sudo zpool list -H -o health "$POOL_NAME" 2>/dev/null || echo "unknown")"
    log_info "Total Size: $(sudo zpool list -H -o size "$POOL_NAME" 2>/dev/null || echo "unknown")"
    log_info "Allocated: $(sudo zpool list -H -o allocated "$POOL_NAME" 2>/dev/null || echo "unknown")"
    log_info "Free: $(sudo zpool list -H -o free "$POOL_NAME" 2>/dev/null || echo "unknown")"
    log_info "Encryption: $(sudo zfs get -H -o value encryption "$POOL_NAME" 2>/dev/null || echo "off")"
    echo "================================"
    echo
    
    log_warning "Verify the pool details above before proceeding with migration"
    log_warning "Once exported, this pool must be imported on Linux to access data"
    echo
    
    # Enhanced confirmation
    read -p "Type 'MIGRATE' to confirm pool export for Linux migration: " confirm
    if [[ "$confirm" != "MIGRATE" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    # Try normal export first
    if ! export_pool; then
        echo
        log_warning "Normal export failed. Detailed error analysis available above."
        log_warning "Force export can be used if the pool is busy, but may cause data loss if files are in use"
        log_warning "Recommendation: Close applications and retry normal export first"
        echo
        read -p "Try force export despite risks? (FORCE): " force_confirm
        
        if [[ "$force_confirm" == "FORCE" ]]; then
            if ! handle_force_export; then
                log_error "Both normal and force export failed"
                log_error "Migration cannot continue - resolve the issues shown above and retry"
                log_info "Consider restarting the system and running the script again"
                exit 1
            fi
        else
            log_info "Operation cancelled by user"
            exit 0
        fi
    fi
    
    # Verify export was successful
    verify_export
    
    # Show Linux import instructions
    show_linux_instructions
    
    # Show rollback instructions
    show_rollback_instructions
    
    echo
    log_success "Migration preparation complete!"
    log_info "You can now safely disconnect the drives and connect them to your Linux system"
}

# Function to handle undo operation
undo_export() {
    log_info "Attempting to import pool back to macOS..."
    
    if zpool import "$POOL_NAME"; then
        log_success "Pool '$POOL_NAME' imported successfully"
        show_pool_status
    else
        log_error "Failed to import pool '$POOL_NAME'"
        log_info "The drives may need to be reconnected or the pool may be in use by another system"
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --undo)
        log_info "Undoing export - importing pool back to macOS..."
        undo_export
        ;;
    --status)
        check_pool_exists
        show_pool_status
        ;;
    --help|"-h")
        echo "Usage: $0 [OPTION]"
        echo "Prepare ZFS pool for migration to Linux"
        echo
        echo "Options:"
        echo "  (no args)   Export pool for migration"
        echo "  --undo      Import pool back to macOS"
        echo "  --status    Show current pool status"
        echo "  --help      Show this help message"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        log_info "Use --help for usage information"
        exit 1
        ;;
esac