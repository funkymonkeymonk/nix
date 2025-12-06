# VM Testing Module

This module provides VM-specific configuration for testing NixOS configurations both locally and in CI/CD environments.

## Usage

Add this module to your NixOS configuration and enable VM testing:

```nix
{
  myConfig.vm.enable = true;
  myConfig.vm.memorySize = 4096;  # Optional: override default memory
  myConfig.vm.cores = 4;          # Optional: override default CPU cores
  myConfig.vm.graphics = true;    # Optional: enable graphics
}
```

## Features

- **Automatic VM Configuration**: Applies VM-specific settings only when building with `build-vm`
- **SSH Access**: Enables SSH with password authentication for testing
- **Port Forwarding**: Forwards SSH port (2222) from host to guest by default
- **Test User**: Creates a test user with sudo access
- **Optimized Settings**: Configures memory, CPU, and disk size for testing
- **Testing Tools**: Includes basic utilities for validation

## VM Options

- `memorySize`: Memory size in MB (default: 2048)
- `cores`: Number of CPU cores (default: 2)
- `graphics`: Enable graphics display (default: false)
- `forwardPorts`: Additional ports to forward from host to guest

## Building and Running

```bash
# Build VM
nix build .#nixosConfigurations.drlight.config.system.build.vm

# Run VM
./result/bin/run-drlight-vm

# Or with flake apps (if configured)
nix run .#vm-drlight
```

## SSH Access

After starting the VM, you can connect via SSH:

```bash
ssh -p 2222 test@localhost
# Password: test
```

## CI/CD Integration

This module is designed to work seamlessly with GitHub Actions and other CI/CD systems that support KVM virtualization.