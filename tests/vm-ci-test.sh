#!/usr/bin/env bash

# CI VM Test Script - Simplified version for GitHub Actions
# Based on https://jnsgr.uk/2024/02/nixos-vms-in-github-actions/
# Usage: ./vm-ci-test.sh <vm-name> <test-type>

set -euo pipefail

VM_NAME="${1:-drlight}"
TEST_TYPE="${2:-basic}"
SSH_PORT="2222"
SSH_USER="test"
SSH_HOST="localhost"

# Set different port for zero VM to avoid conflicts
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

# SSH command wrapper optimized for CI
ssh_cmd() {
    ssh -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        -p "$SSH_PORT" \
        "${SSH_USER}@${SSH_HOST}" \
        "$@"
}

# Quick connectivity test
test_connectivity() {
    log_info "Testing basic connectivity..."
    
    if ssh_cmd "echo 'SSH connection successful'" >/dev/null 2>&1; then
        log_success "SSH connectivity test passed"
        return 0
    else
        log_error "SSH connectivity test failed"
        return 1
    fi
}

# Test basic system functionality
test_basic() {
    log_info "Running basic system tests..."
    
    # Test Nix availability
    if ssh_cmd "which nix" >/dev/null; then
        log_success "Nix is available"
    else
        log_error "Nix is not available"
        return 1
    fi
    
    # Test basic commands
    if ssh_cmd "systemctl is-active sshd" | grep -q "active"; then
        log_success "SSH service is active"
    else
        log_warning "SSH service is not active"
    fi
    
    return 0
}

# Test system configuration
test_system() {
    log_info "Running system configuration tests..."
    
    # Test system state
    if ssh_cmd "cat /etc/os-release | grep -q 'NixOS'"; then
        log_success "Running on NixOS"
    else
        log_error "Not running on NixOS"
        return 1
    fi
    
    # Test if configuration was applied
    if ssh_cmd "test -f /etc/nixos/configuration.nix"; then
        log_success "NixOS configuration exists"
    else
        log_warning "NixOS configuration not found"
    fi
    
    return 0
}

# Test development environment
test_development() {
    log_info "Running development environment tests..."
    
    # Test for development tools
    local dev_tools=("git" "vim" "curl")
    local missing_count=0
    
    for tool in "${dev_tools[@]}"; do
        if ssh_cmd "which $tool" >/dev/null; then
            log_success "$tool is available"
        else
            log_warning "$tool is not available"
            ((missing_count++))
        fi
    done
    
    # Test git configuration if git is available
    if ssh_cmd "which git" >/dev/null; then
        if ssh_cmd "git config --global user.name" >/dev/null 2>&1; then
            log_success "Git configuration exists"
        else
            log_warning "Git configuration not found"
        fi
    fi
    
    return 0
}

# Test home-manager if enabled
test_home_manager() {
    log_info "Running home-manager tests..."
    
    # Check if home-manager is available
    if ssh_cmd "which home-manager" >/dev/null; then
        log_success "home-manager is available"
        
        # Test if home-manager generation exists
        if ssh_cmd "home-manager generations" >/dev/null 2>&1; then
            log_success "home-manager generations exist"
        else
            log_warning "No home-manager generations found"
        fi
    else
        log_warning "home-manager is not available"
    fi
    
    return 0
}

# Test package availability
test_packages() {
    log_info "Running package availability tests..."
    
    # Test for common packages
    local common_packages=("htop" "tree")
    local available_count=0
    
    for pkg in "${common_packages[@]}"; do
        if ssh_cmd "which $pkg" >/dev/null; then
            log_success "$pkg is available"
            ((available_count++))
        else
            log_warning "$pkg is not available"
        fi
    done
    
    log_info "Available packages: $available_count/${#common_packages[@]}"
    return 0
}

# Main test execution
main() {
    log_info "Starting CI VM tests for ${VM_NAME} (${TEST_TYPE})"
    
    # Always test connectivity first
    if ! test_connectivity; then
        log_error "VM connectivity failed - aborting tests"
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
        "full")
            test_basic || ((failed_tests++))
            test_system || ((failed_tests++))
            test_development || ((failed_tests++))
            test_home_manager || ((failed_tests++))
            test_packages || ((failed_tests++))
            ;;
        *)
            log_error "Unknown test type: ${TEST_TYPE}"
            echo "Available test types: basic, system, development, home-manager, packages, full"
            exit 1
            ;;
    esac
    
    # Summary
    echo
    log_info "CI Test Summary for ${VM_NAME}"
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
    echo "Usage: $0 <vm-name> <test-type>"
    echo ""
    echo "VM names: drlight, zero"
    echo "Test types: basic, system, development, home-manager, packages, full"
    echo ""
    echo "Examples:"
    echo "  $0 drlight basic"
    echo "  $0 zero full"
    exit 1
fi

# Run main function
main "$@"