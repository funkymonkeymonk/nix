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

# Set script start time for timeout tracking
SCRIPT_START_TIME=$(date +%s)
SCRIPT_TIMEOUT=480  # 8 minutes

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

# Check if script is approaching timeout
check_timeout() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - SCRIPT_START_TIME))
    
    if [[ $elapsed -gt $((SCRIPT_TIMEOUT - 60)) ]]; then
        log_warning "Approaching timeout: ${elapsed}s elapsed, ${SCRIPT_TIMEOUT}s limit"
    fi
    
    if [[ $elapsed -gt $SCRIPT_TIMEOUT ]]; then
        log_error "Script timeout exceeded: ${elapsed}s elapsed, ${SCRIPT_TIMEOUT}s limit"
        exit 124  # timeout exit code
    fi
}

# Logging functions
log_info() {
    check_timeout
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

# SSH command wrapper optimized for CI with better error handling
ssh_cmd() {
    local output
    local exit_code
    
    # Capture both output and exit code
    if output=$(ssh -o UserKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -p "$SSH_PORT" \
        "${SSH_USER}@${SSH_HOST}" \
        "$@" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Return the output and exit code
    echo "$output"
    return $exit_code
}

# Quick connectivity test with retry logic
test_connectivity() {
    log_info "Testing basic connectivity..."
    
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "SSH connection attempt $attempt/$max_attempts"
        
        if ssh_cmd "echo 'SSH connection successful'" >/dev/null 2>&1; then
            log_success "SSH connectivity test passed after $attempt attempts"
            return 0
        else
            log_warning "SSH connection attempt $attempt failed"
            if [[ $attempt -eq $max_attempts ]]; then
                log_error "SSH connectivity test failed after $max_attempts attempts"
                # Debug information
                log_info "Debugging SSH connectivity:"
                log_info "SSH Port: $SSH_PORT"
                log_info "SSH User: $SSH_USER"
                log_info "SSH Host: $SSH_HOST"
                return 1
            fi
            sleep 3
            ((attempt++))
        fi
    done
}

# Test basic system functionality
test_basic() {
    log_info "Running basic system tests..."
    
    # Test Nix availability with error handling
    if nix_output=$(ssh_cmd "which nix" 2>&1); then
        log_success "Nix is available at: $nix_output"
    else
        log_error "Nix is not available: $nix_output"
        return 1
    fi
    
    # Test basic commands with better error handling
    if sshd_output=$(ssh_cmd "systemctl is-active sshd" 2>&1); then
        if echo "$sshd_output" | grep -q "active"; then
            log_success "SSH service is active"
        else
            log_warning "SSH service status: $sshd_output"
        fi
    else
        log_warning "Could not check SSH service status: $sshd_output"
    fi
    
    # Test basic system info
    if ssh_cmd "uname -a" >/dev/null 2>&1; then
        log_success "System information accessible"
    else
        log_warning "Could not retrieve system information"
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

# Function to run a test with timeout
run_test_with_timeout() {
    local test_function="$1"
    local timeout_seconds="${2:-60}"  # Default 60 second timeout
    
    # Run the test in background with timeout
    timeout "$timeout_seconds" bash -c "$test_function" 2>&1
    local exit_code=$?
    
    if [[ $exit_code -eq 124 ]]; then
        log_error "Test timed out after ${timeout_seconds} seconds"
        return 124
    elif [[ $exit_code -ne 0 ]]; then
        log_error "Test failed with exit code $exit_code"
        return $exit_code
    fi
    
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
    
    # Run tests based on type with error handling
    case "$TEST_TYPE" in
        "basic")
            if ! test_basic; then
                ((failed_tests++))
                log_error "Basic tests failed"
            fi
            ;;
        "system")
            if ! test_basic; then
                ((failed_tests++))
                log_error "Basic tests failed"
            fi
            if ! test_system; then
                ((failed_tests++))
                log_error "System tests failed"
            fi
            ;;
        "development")
            if ! test_basic; then
                ((failed_tests++))
                log_error "Basic tests failed"
            fi
            if ! test_development; then
                ((failed_tests++))
                log_error "Development tests failed"
            fi
            ;;
        "home-manager")
            if ! test_basic; then
                ((failed_tests++))
                log_error "Basic tests failed"
            fi
            if ! test_home_manager; then
                ((failed_tests++))
                log_error "Home-manager tests failed"
            fi
            ;;
        "packages")
            if ! test_basic; then
                ((failed_tests++))
                log_error "Basic tests failed"
            fi
            if ! test_packages; then
                ((failed_tests++))
                log_error "Package tests failed"
            fi
            ;;
        "full")
            if ! test_basic; then
                ((failed_tests++))
                log_error "Basic tests failed"
            fi
            if ! test_system; then
                ((failed_tests++))
                log_error "System tests failed"
            fi
            if ! test_development; then
                ((failed_tests++))
                log_error "Development tests failed"
            fi
            if ! test_home_manager; then
                ((failed_tests++))
                log_error "Home-manager tests failed"
            fi
            if ! test_packages; then
                ((failed_tests++))
                log_error "Package tests failed"
            fi
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