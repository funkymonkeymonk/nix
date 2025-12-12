#!/usr/bin/env bash

# VM Execution Helper - Simplified for CI/CD
# Based on https://jnsgr.uk/2024/02/nixos-vms-in-github-actions/
# Usage: ./vm-exec-simple.sh <vm-name> <command>

set -euo pipefail

VM_NAME="${1:-drlight}"
COMMAND="${2:-echo 'No command specified'}"
SSH_PORT="2222"
SSH_USER="test"
SSH_HOST="localhost"

# Set different port for zero VM to avoid conflicts
if [[ "$VM_NAME" == "zero" ]]; then
    SSH_PORT="2223"
fi

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

# Wait for VM to be ready (simplified for CI)
wait_for_vm() {
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh_cmd "echo 'VM is ready'" >/dev/null 2>&1; then
            echo "VM ready after $attempt attempts"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            echo "VM failed to become ready after $max_attempts attempts"
            return 1
        fi
        
        sleep 2
        ((attempt++))
    done
}

# Main execution
main() {
    echo "Executing command on ${VM_NAME} VM..."
    
    # Wait for VM to be ready
    if ! wait_for_vm; then
        echo "VM is not accessible"
        exit 1
    fi
    
    # Execute the command
    echo "Running: ${COMMAND}"
    if ssh_cmd "${COMMAND}"; then
        echo "Command executed successfully"
        exit 0
    else
        echo "Command execution failed"
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