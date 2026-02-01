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

# Configuration
POOL_NAME="backup"

# Function to check if pool exists
check_pool_exists() {
    if ! zpool list "$POOL_NAME" >/dev/null 2>&1; then
        log_error "ZFS pool '$POOL_NAME' does not exist"
        log_info "Available pools:"
        zpool list
        exit 1
    fi
    log_success "ZFS pool '$POOL_NAME' found"
}

# Function to show pool status
show_pool_status() {
    log_info "Current pool status:"
    zpool status "$POOL_NAME"
    echo
    log_info "Pool datasets:"
    zfs list -r "$POOL_NAME"
}

# Function to export pool safely
export_pool() {
    log_info "Exporting ZFS pool '$POOL_NAME' for migration..."
    
    # Check if any datasets are busy
    if zfs list -r "$POOL_NAME" | grep -q "legacy"; then
        log_warning "Some datasets may have legacy mountpoints"
        log_warning "Make sure all datasets are unmounted before proceeding"
    fi
    
    # Attempt to unmount the pool
    if ! zpool export "$POOL_NAME"; then
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
    echo "   sudo zpool import backup"
    echo "   # You'll be prompted for the encryption passphrase"
    echo
    echo "4. Verify import:"
    echo "   sudo zpool status backup"
    echo "   sudo zfs list -r backup"
    echo
    echo "5. Create mountpoints if needed:"
    echo "   sudo mkdir -p /mnt/backup"
    echo "   sudo zfs set mountpoint=/mnt/backup backup"
    echo
    echo "6. Enable auto-mount on boot (optional):"
    echo "   sudo zpool set cachefile=/etc/zfs/zpool.cache backup"
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
    echo "   sudo zpool import backup"
    echo "   # You'll be prompted for the encryption passphrase"
    echo
    echo "3. The pool should mount automatically at /Volumes/backup"
    echo
    log_warning "Note: This should only be needed if the migration fails"
}

# Function to handle force export option
handle_force_export() {
    log_warning "Attempting force export..."
    
    # Try to unmount all datasets first
    log_info "Attempting to unmount all datasets..."
    zfs unmount -a -r "$POOL_NAME" 2>/dev/null || true
    
    # Force export
    if zpool export -f "$POOL_NAME"; then
        log_success "Force export successful"
        return 0
    else
        log_error "Force export failed"
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
    
    # Ask for confirmation
    read -p "Do you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    # Try normal export first
    if ! export_pool; then
        echo
        log_warning "Normal export failed. Would you like to try force export?"
        log_warning "Force export can be used if the pool is busy, but may cause data loss if files are in use"
        read -p "Try force export? (yes/no): " force_confirm
        
        if [[ "$force_confirm" == "yes" ]]; then
            if ! handle_force_export; then
                log_error "Both normal and force export failed"
                log_info "Please check what is using the pool and try again"
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