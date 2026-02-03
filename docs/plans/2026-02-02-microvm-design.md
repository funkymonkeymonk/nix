# Microvm Integration Design

## Overview

Add microvm.nix support to create lightweight, fast-booting NixOS VMs that reuse the existing modular configuration system.

## Goals

- Local development testing
- Ephemeral dev environments
- CI/CD testing capability
- Remote server deployment (future)

## Constraints

- Cross-platform: macOS (via Colima) and native Linux
- Full reuse of existing roles and modules
- x86_64-linux guest architecture
- Start with single `dev-vm` profile, expand as needed

## Architecture

### Flake Structure

Add microvm.nix as input:

```nix
inputs.microvm.url = "github:astro/microvm.nix";
inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";
```

New flake output:

```nix
microvm.nixosConfigurations.dev-vm = mkMicrovm "dev-vm" ["developer" "llm-client"];
```

### Module Composition

The `mkMicrovm` helper composes:

1. Base configuration (shared with all systems)
2. Common modules (options, users, shell, onepassword, cachix)
3. `modules/microvm/default.nix` - microvm.nix integration
4. `modules/microvm/guest.nix` - guest-specific config
5. `os/microvm.nix` - platform config (like os/nixos.nix)
6. `targets/microvms/dev-vm.nix` - target-specific config
7. `mkBundleModule "linux" [roles]` - existing role system

### File Structure

```
modules/
  microvm/
    default.nix      # Main microvm module
    guest.nix        # Guest-specific config
os/
  microvm.nix        # Platform config for microvms
targets/
  microvms/
    dev-vm.nix       # Dev VM target
```

## VM Configuration

### dev-vm Profile

| Setting | Value |
|---------|-------|
| Roles | base, developer, llm-client |
| Memory | 4GB |
| CPUs | 4 |
| Hypervisor | cloud-hypervisor |
| Networking | User-mode (NAT) |
| Root FS | tmpfs |
| Shared mounts | virtiofs |

### Technical Decisions

- **Hypervisor:** cloud-hypervisor (good performance, maintained)
- **Networking:** User-mode networking (NAT, no root required)
- **Storage:** virtiofs for host mounts, tmpfs for root (ephemeral)
- **Boot:** Direct kernel boot (~2s boot time)

## Cross-Platform Execution

### Linux Hosts (drlight, zero)

Direct execution using KVM:

```bash
nix run .#microvm.nixosConfigurations.dev-vm.config.microvm.run
# Or
task microvm:run -- dev-vm
```

### macOS Hosts (wweaver, MegamanX)

Run inside Colima (Linux VM with nested virtualization):

```bash
# Colima provides Linux/KVM environment
colima start --arch x86_64 --vm-type vz --mount-type virtiofs

# Then run microvm inside
task microvm:run -- dev-vm
```

## Task Automation

New Taskfile.yml tasks:

```yaml
microvm:
  build:   # Build microvm image
  run:     # Start microvm (platform-aware)
  stop:    # Stop running microvm
  ssh:     # SSH into running microvm
  shell:   # Get shell in microvm
```

## Implementation Files

| File | Action | Purpose |
|------|--------|---------|
| `flake.nix` | Modify | Add microvm input, outputs, mkMicrovm |
| `modules/microvm/default.nix` | Create | Main microvm module |
| `modules/microvm/guest.nix` | Create | Guest-specific config |
| `os/microvm.nix` | Create | Platform config |
| `targets/microvms/dev-vm.nix` | Create | Dev VM target |
| `Taskfile.yml` | Modify | Add microvm tasks |

## Future Extensions (Not in Scope)

- Additional VM profiles (ci-vm, test-vm, llm-vm)
- Persistent storage for VMs
- Remote deployment tooling
- CI pipeline integration
- GPU passthrough for llm-vm
