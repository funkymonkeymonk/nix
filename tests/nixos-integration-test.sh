#!/usr/bin/env bash

# NixOS Integration Test Script
# Tests core NixOS functionality in the VM
# Usage: ./nixos-integration-test.sh

set -euo pipefail

# Set script start time for timeout tracking
SCRIPT_START_TIME=$(date +%s)
SCRIPT_TIMEOUT=300  # 5 minutes for integration tests

# Check if script is approaching timeout
check_timeout() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - SCRIPT_START_TIME))
    
    if [[ $elapsed -gt $((SCRIPT_TIMEOUT - 30)) ]]; then
        log_warning "Approaching timeout: ${elapsed}s elapsed, ${SCRIPT_TIMEOUT}s limit"
    fi
    
    if [[ $elapsed -gt $SCRIPT_TIMEOUT ]]; then
        log_error "Script timeout exceeded: ${elapsed}s elapsed, ${SCRIPT_TIMEOUT}s limit"
        exit 124  # timeout exit code
    fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    check_timeout
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test NixOS basic functionality
test_nixos_basic() {
    log_info "Testing NixOS basic functionality..."
    
    # Test if we're running on NixOS
    if grep -q "NixOS" /etc/os-release; then
        log_success "Confirmed running on NixOS"
        log_info "OS Release: $(grep 'PRETTY_NAME' /etc/os-release | cut -d'"' -f2)"
    else
        log_error "Not running on NixOS"
        log_info "OS Release content:"
        cat /etc/os-release
        return 1
    fi
    
    # Test Nix store with better error handling
    if nix_version=$(nix --version 2>&1); then
        log_success "Nix command is available: $nix_version"
    else
        log_error "Nix command not found or not working: $nix_version"
        return 1
    fi
    
    # Test systemd with better error handling
    if systemd_version=$(systemctl --version 2>&1 | head -1); then
        log_success "systemd is working: $systemd_version"
    else
        log_error "systemd not working: $systemd_version"
        return 1
    fi
    
    return 0
}

# Test NixOS configuration management
test_nixos_config() {
    log_info "Testing NixOS configuration..."
    
    # Check if configuration exists
    if [[ -f /etc/nixos/configuration.nix ]]; then
        log_success "NixOS configuration exists"
    else
        log_warning "NixOS configuration not found in /etc/nixos/"
    fi
    
    # Test if we can query the system
    if nix-store -q --references /run/current-system >/dev/null 2>&1; then
        log_success "Can query current system references"
    else
        log_warning "Cannot query system references"
    fi
    
    return 0
}

# Test package management
test_package_management() {
    log_info "Testing package management..."
    
    # Test if common packages are available
    local test_packages=("git" "curl" "vim")
    local available=0
    
    for pkg in "${test_packages[@]}"; do
        if command -v "$pkg" >/dev/null; then
            log_success "$pkg is available"
            ((available++))
        else
            log_warning "$pkg is not available"
        fi
    done
    
    log_info "Available packages: $available/${#test_packages[@]}"
    
    # Test nix-env
    if nix-env --version >/dev/null 2>&1; then
        log_success "nix-env is working"
    else
        log_warning "nix-env not working"
    fi
    
    return 0
}

# Test services
test_services() {
    log_info "Testing system services..."
    
    # Test SSH service with better error handling
    if sshd_status=$(systemctl is-active sshd 2>&1); then
        log_success "SSH service is active: $sshd_status"
    else
        log_error "SSH service is not active: $sshd_status"
        # Show service status for debugging
        systemctl status sshd --no-pager || true
        return 1
    fi
    
    # Test networking with better error handling
    if network_status=$(systemctl is-active network-online.target 2>&1); then
        log_success "Network is online: $network_status"
    else
        log_warning "Network target not active: $network_status"
        # Show network status for debugging
        systemctl status network-online.target --no-pager || true
    fi
    
    # Test basic network connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_success "Basic network connectivity working"
    else
        log_warning "Basic network connectivity failed"
    fi
    
    return 0
}

# Test user environment
test_user_environment() {
    log_info "Testing user environment..."
    
    # Test user home directory
    if [[ -d "$HOME" ]]; then
        log_success "Home directory exists: $HOME"
    else
        log_error "Home directory not found"
        return 1
    fi
    
    # Test shell
    if [[ -n "$SHELL" ]]; then
        log_success "Shell is set to: $SHELL"
    else
        log_warning "Shell not set"
    fi
    
    # Test PATH
    if [[ -n "$PATH" ]]; then
        log_success "PATH is set"
    else
        log_error "PATH not set"
        return 1
    fi
    
    return 0
}

# Test development environment
test_development_environment() {
    log_info "Testing development environment..."
    
    # Test git
    if command -v git >/dev/null; then
        log_success "Git is available"
        
        # Test git configuration
        if git config --global user.name >/dev/null 2>&1; then
            log_success "Git is configured"
        else
            log_warning "Git not configured"
        fi
    else
        log_warning "Git not available"
    fi
    
    # Test text editor
    if command -v vim >/dev/null || command -v nano >/dev/null; then
        log_success "Text editor is available"
    else
        log_warning "No text editor found"
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting NixOS Integration Test"
    
    local failed_tests=0
    
    # Run all tests
    test_nixos_basic || ((failed_tests++))
    test_nixos_config || ((failed_tests++))
    test_package_management || ((failed_tests++))
    test_services || ((failed_tests++))
    test_user_environment || ((failed_tests++))
    test_development_environment || ((failed_tests++))
    
    # Summary
    echo
    log_info "Integration Test Summary"
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All integration tests passed! ✅"
        exit 0
    else
        log_error "$failed_tests test(s) failed! ❌"
        exit 1
    fi
}

# Run main function
main "$@"