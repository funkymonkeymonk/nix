# VM Testing Scripts

This directory contains scripts for testing NixOS VM configurations both locally and in CI/CD environments.

## Scripts

### vm-test.sh

Comprehensive testing script for NixOS VM configurations.

**Usage:**
```bash
./vm-test.sh <vm-name> [test-type]
```

**VM Names:**
- `drlight` - Development workstation with creative tools
- `zero` - Gaming workstation with Steam

**Test Types:**
- `basic` - Basic connectivity and SSH access
- `system` - System configuration and services
- `development` - Development environment and tools
- `home-manager` - Home-manager configuration
- `packages` - Package availability and installation
- `performance` - System performance metrics
- `full` - All tests combined

**Examples:**
```bash
# Basic connectivity test
./vm-test.sh drlight basic

# Full test suite
./vm-test.sh zero full

# Development environment test
./vm-test.sh drlight development
```

### vm-exec.sh

Simple command execution wrapper for VMs, useful for CI/CD.

**Usage:**
```bash
./vm-exec.sh <vm-name> <command>
```

**Examples:**
```bash
# List home directory
./vm-exec.sh drlight "ls -la /home"

# Check service status
./vm-exec.sh zero "systemctl status sshd"

# Run custom test script
./vm-exec.sh drlight "/path/to/custom/test.sh"
```

## VM Configuration

The scripts expect VMs to be configured with:
- SSH enabled on port 2222 (drlight) or 2223 (zero)
- Test user with password 'test' and sudo access
- Basic networking tools installed

## Integration with Taskfile

These scripts are integrated with the Taskfile for easy usage:

```bash
# Test VM configurations
task vm:test:drlight
task vm:test:zero
task vm:test:all

# Run VMs
task vm:drlight
task vm:zero

# SSH into VMs
task vm:ssh:drlight
task vm:ssh:zero
```

## CI/CD Usage

In GitHub Actions, these scripts can be used to validate VM configurations:

```yaml
- name: Test VM Configuration
  run: |
    # Start VM in background
    nix run .#vm-drlight -- -daemonize -display none
    
    # Run tests
    ./tests/vm-test.sh drlight full
```

## Troubleshooting

### SSH Connection Issues
- Ensure VM is running and accessible
- Check port forwarding (2222 for drlight, 2223 for zero)
- Verify SSH service is enabled in VM

### Test Failures
- Check VM logs with `journalctl -u sshd`
- Verify user permissions and sudo access
- Ensure required packages are installed

### Performance Issues
- Increase VM memory and CPU cores in configuration
- Check disk space usage
- Monitor system resources during tests