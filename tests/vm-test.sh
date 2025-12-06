#!/usr/bin/env bash

# VM Test Script for NixOS Configurations
# Usage: ./vm-test.sh <vm-name> [test-type]
# Example: ./vm-test.sh drlight basic

set -euo pipefail

VM_NAME="${1:-drlight}"
TEST_TYPE="${2:-basic}"
SSH_PORT="2222"
SSH_USER="test"
SSH_HOST="localhost"

# Set different port for zero VM
if [[ "$VM_NAME" == "zero" ]]; then
    SSH_PORT="2223"
fi

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

# SSH command wrapper
ssh_cmd() {
    ssh -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        -p "$SSH_PORT" \
        "${SSH_USER}@${SSH_HOST}" \
        "$@"
}

# Wait for VM to be ready
wait_for_vm() {
    log_info "Waiting for VM to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh_cmd "echo 'VM is ready'" >/dev/null 2>&1; then
            log_success "VM is ready after ${attempt} attempts"
            return 0
        fi
        
        log_info "Attempt ${attempt}/${max_attempts}: VM not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    log_error "VM failed to become ready after ${max_attempts} attempts"
    return 1
}

# Basic connectivity tests
test_basic() {
    log_info "Running basic connectivity tests..."
    
    # Test SSH connectivity
    if ssh_cmd "echo 'SSH connection successful'"; then
        log_success "SSH connectivity test passed"
    else
        log_error "SSH connectivity test failed"
        return 1
    fi
    
    # Test user permissions
    if ssh_cmd "sudo -n whoami" | grep -q "root"; then
        log_success "Sudo access test passed"
    else
        log_error "Sudo access test failed"
        return 1
    fi
    
    # Test basic commands
    if ssh_cmd "which nix" >/dev/null; then
        log_success "Nix availability test passed"
    else
        log_error "Nix availability test failed"
        return 1
    fi
    
    return 0
}

# System configuration tests
test_system() {
    log_info "Running system configuration tests..."
    
    # Test system state version
    local state_version
    state_version=$(ssh_cmd "cat /etc/nixos/state-version" 2>/dev/null || echo "unknown")
    log_info "System state version: ${state_version}"
    
    # Test if services are running
    if ssh_cmd "systemctl is-active sshd" | grep -q "active"; then
        log_success "SSH service is active"
    else
        log_warning "SSH service is not active"
    fi
    
    # Test network connectivity
    if ssh_cmd "ping -c 1 8.8.8.8" >/dev/null 2>&1; then
        log_success "Network connectivity test passed"
    else
        log_warning "Network connectivity test failed (may be expected in VM)"
    fi
    
    return 0
}

# Development environment tests
test_development() {
    log_info "Running development environment tests..."
    
    # Test if development tools are available
    local dev_tools=("git" "vim" "curl" "wget")
    local missing_tools=()
    
    for tool in "${dev_tools[@]}"; do
        if ssh_cmd "which $tool" >/dev/null; then
            log_success "$tool is available"
        else
            log_warning "$tool is not available"
            missing_tools+=("$tool")
        fi
    done
    
    # Test git configuration if available
    if ssh_cmd "which git" >/dev/null; then
        if ssh_cmd "git config --global user.name" >/dev/null; then
            log_success "Git configuration exists"
        else
            log_warning "Git configuration not found"
        fi
    fi
    
    return 0
}

# Home-manager tests
test_home_manager() {
    log_info "Running home-manager tests..."
    
    # Check if home-manager is available
    if ssh_cmd "which home-manager" >/dev/null; then
        log_success "home-manager is available"
        
        # Test home-manager generation
        if ssh_cmd "home-manager generations" >/dev/null; then
            log_success "home-manager generations exist"
        else
            log_warning "No home-manager generations found"
        fi
    else
        log_warning "home-manager is not available"
    fi
    
    return 0
}

# Package availability tests
test_packages() {
    log_info "Running package availability tests..."
    
    # Test for common packages based on roles
    local common_packages=("htop" "tree")
    local dev_packages=("git" "vim")
    local creative_packages=()  # Add creative tools if needed
    
    for pkg in "${common_packages[@]}"; do
        if ssh_cmd "nix-store -q $(which $pkg 2>/dev/null)" >/dev/null 2>&1; then
            log_success "$pkg is available in nix store"
        else
            log_warning "$pkg is not available"
        fi
    done
    
    return 0
}

# Performance tests
test_performance() {
    log_info "Running performance tests..."
    
    # Test disk space
    local disk_usage
    disk_usage=$(ssh_cmd "df -h /" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -lt 90 ]]; then
        log_success "Disk usage is acceptable: ${disk_usage}%"
    else
        log_warning "High disk usage: ${disk_usage}%"
    fi
    
    # Test memory usage
    local mem_usage
    mem_usage=$(ssh_cmd "free | grep Mem | awk '{printf \"%.0f\", \$3/\$2 * 100.0}'")
    log_info "Memory usage: ${mem_usage}%"
    
    return 0
}

# Main test execution
main() {
    log_info "Starting VM tests for ${VM_NAME} (${TEST_TYPE})"
    
    # Wait for VM to be ready
    if ! wait_for_vm; then
        log_error "VM is not accessible. Make sure it's running on port ${SSH_PORT}"
        exit 1
    fi
    
    local failed_tests=0
    
    # Run tests based on type
    case "$TEST_TYPE" in
        "basic")
            test_basic || ((failed_tests++))
            ;;
        "system")
            test_basic || ((failed_tests++))
            test_system || ((failed_tests++))
            ;;
        "development")
            test_basic || ((failed_tests++))
            test_development || ((failed_tests++))
            ;;
        "home-manager")
            test_basic || ((failed_tests++))
            test_home_manager || ((failed_tests++))
            ;;
        "packages")
            test_basic || ((failed_tests++))
            test_packages || ((failed_tests++))
            ;;
        "performance")
            test_basic || ((failed_tests++))
            test_performance || ((failed_tests++))
            ;;
        "full")
            test_basic || ((failed_tests++))
            test_system || ((failed_tests++))
            test_development || ((failed_tests++))
            test_home_manager || ((failed_tests++))
            test_packages || ((failed_tests++))
            test_performance || ((failed_tests++))
            ;;
        *)
            log_error "Unknown test type: ${TEST_TYPE}"
            echo "Available test types: basic, system, development, home-manager, packages, performance, full"
            exit 1
            ;;
    esac
    
    # Summary
    echo
    log_info "Test Summary for ${VM_NAME}"
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All tests passed! ✅"
        exit 0
    else
        log_error "${failed_tests} test(s) failed! ❌"
        exit 1
    fi
}

# Show usage if no arguments provided
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <vm-name> [test-type]"
    echo ""
    echo "VM names: drlight, zero"
    echo "Test types: basic, system, development, home-manager, packages, performance, full"
    echo ""
    echo "Examples:"
    echo "  $0 drlight basic"
    echo "  $0 zero full"
    exit 1
fi

# Run main function
main "$@"