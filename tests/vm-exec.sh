#!/usr/bin/env bash

# VM Execution Helper for CI/CD
# Usage: ./vm-exec.sh <vm-name> <command>
# Example: ./vm-exec.sh drlight "ls -la /home"

set -euo pipefail

VM_NAME="${1:-drlight}"
COMMAND="${2:-echo 'No command specified'}"
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

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
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
        
        sleep 2
        ((attempt++))
    done
    
    log_error "VM failed to become ready after ${max_attempts} attempts"
    return 1
}

# Main execution
main() {
    log_info "Executing command on ${VM_NAME} VM..."
    
    # Wait for VM to be ready
    if ! wait_for_vm; then
        log_error "VM is not accessible"
        exit 1
    fi
    
    # Execute the command
    log_info "Running: ${COMMAND}"
    if ssh_cmd "${COMMAND}"; then
        log_success "Command executed successfully"
        exit 0
    else
        log_error "Command execution failed"
        exit 1
    fi
}

# Show usage if no arguments provided
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <vm-name> <command>"
    echo ""
    echo "VM names: drlight, zero"
    echo ""
    echo "Examples:"
    echo "  $0 drlight 'ls -la /home'"
    echo "  $0 zero 'systemctl status sshd'"
    exit 1
fi

# Run main function
main "$@"