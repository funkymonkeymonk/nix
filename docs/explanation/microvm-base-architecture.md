---
title: "MicroVM Base Configuration"
description: "All MicroVMs inherit from a shared base configuration. Understand the layering architecture and how to customize individual VMs."
type: explanation
audience: user
last-reviewed: 2026-04-18
---

# MicroVM Base Configuration Architecture

This repository uses a **base image pattern** for MicroVMs. All VMs share a common foundation (modules/microvm/base.nix) and layer their specific customizations on top.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    VM-Specific Layer                        │
│  (targets/microvms/<name>.nix)                              │
│  • Service configuration (openclaw, matrix, etc.)         │
│  • Per-VM networking (IP, hostname)                         │
│  • VM-specific packages                                     │
│  • Secrets configuration                                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   Network Adapter Layer                     │
│  (modules/microvm/default.nix)                              │
│  • Bridge networking from myConfig.microvm options        │
│  • IP address configuration                                 │
│  • Gateway configuration                                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     Base MicroVM                            │
│  (modules/microvm/base.nix)                                 │
│  • SSH daemon                                               │
│  • Cloud-init hostname application                        │
│  • Basic packages (vim, git, htop, curl, jq)              │
│  • System defaults                                          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                  NixOS Foundation                           │
│  (modules/nixos/base.nix, home-manager, etc.)             │
│  • User configuration                                       │
│  • Shell setup                                            │
│  • Development tools                                        │
└─────────────────────────────────────────────────────────────┘
```

## The Base Configuration

**File:** `modules/microvm/base.nix`

All MicroVMs automatically inherit:

### Services
- **SSH**: OpenSSH with key-based auth (no passwords)
- **Cloud-init**: Applies hostname from host-mounted config

### Packages
- `vim` - Text editor
- `git` - Version control
- `htop` - Process viewer
- `curl` - HTTP client
- `jq` - JSON processor

### Network Defaults
- Bridge networking ready
- DNS: `192.168.83.1` (the host)
- DHCP disabled (static IPs)

### Security
- Firewall disabled (MicroVM isolation)
- Auto-upgrade disabled (host controls updates)

## Host-Side Management

**File:** `modules/roles/microvm-host.nix`

The host uses `myConfig.microvms` to define which VMs to run:

```nix
# In your host configuration (e.g., machine-types/server.nix)
{
  myConfig.roles.microvm-host.enable = true;

  myConfig.microvms = {
    openclaw = {
      ip = "192.168.83.16";
      memory = 2048;
      vcpus = 4;
    };

    matrix = {
      ip = "192.168.83.15";
      autostart = false;  # Don't start on boot
    };
  };
}
```

### What the Host Provides

| Attribute | Default | Description |
|-----------|---------|-------------|
| `ip` | **Required** | Static IP (e.g., `192.168.83.16`) |
| `flake` | `.#microvm.nixosConfigurations.<name>` | Flake reference |
| `mac` | Auto-generated | MAC address (deterministic from name) |
| `autostart` | `true` | Start on boot |
| `memory` | `1024` | RAM in MB |
| `vcpus` | `2` | Virtual CPUs |
| `extraShares` | `[]` | Additional virtiofs mounts |
| `extraInterfaces` | `[]` | Additional network interfaces |
| `customConfig` | `{}` | Raw microvm.vms attributes |

## Creating a New MicroVM

### Step 1: Create VM Target File

Create `targets/microvms/myapp.nix` with ONLY your specific configuration:

```nix
# targets/microvms/myapp.nix
{ pkgs, ... }: {
  # VM identity
  networking.hostName = "myapp";
  time.timeZone = "America/New_York";

  # Network (IP provided by host, just enable)
  myConfig.microvm = {
    enable = true;
    ipAddress = "192.168.83.20";  # Will be overridden by host
    gateway = "192.168.83.1";      # Will be overridden by host
  };

  # Your application
  services.myapp = {
    enable = true;
    port = 8080;
  };

  # VM-specific packages (base packages already included)
  environment.systemPackages = with pkgs; [
    # Add only what you need beyond vim, git, htop, curl, jq
    postgresql
  ];

  # SSH keys
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."
  ];

  system.stateVersion = "25.05";
}
```

### Step 2: Add to Flake

Register the VM in `flake.nix`:

```nix
microvm.nixosConfigurations = {
  # ... existing VMs
  myapp = mkMicrovm "myapp" {
    # Optional role enables
    roles.database.enable = true;
  };
};
```

### Step 3: Add to Host

Configure the host to run the VM:

```nix
# In your host configuration
{
  myConfig.microvms.myapp = {
    ip = "192.168.83.20";
    memory = 4096;  # 4GB
    vcpus = 4;
    extraShares = [
      {
        tag = "data";
        source = "/var/lib/myapp-data";
        mountPoint = "/data";
        proto = "virtiofs";
      }
    ];
  };
}
```

### Step 4: Deploy

```bash
# On host
sudo nixos-rebuild switch

# Check status
systemctl status microvm-myapp

# Access VM
ssh root@192.168.83.20
```

## Customization Patterns

### Pattern 1: Simple VM (High-Level API)

Use `myConfig.microvms` for common cases:

```nix
myConfig.microvms.webserver = {
  ip = "192.168.83.30";
  memory = 512;
  vcpus = 1;
};
```

### Pattern 2: Complex VM (Direct microvm.vms)

For special cases, use the low-level API directly:

```nix
# Override or extend the generated config
microvm.vms.router = {
  flake = ".#microvm.nixosConfigurations.router";
  interfaces = [
    { type = "tap"; id = "microvm-router-lan"; mac = "02:00:00:00:00:40"; }
    { type = "tap"; id = "microvm-router-wan"; mac = "02:00:00:00:00:41"; }
  ];
  # ... complex networking
};
```

### Pattern 3: Custom Shares

Mount host directories into the VM:

```nix
myConfig.microvms.fileserver = {
  ip = "192.168.83.40";
  extraShares = [
    {
      tag = "media";
      source = "/mnt/media";
      mountPoint = "/media";
      proto = "virtiofs";
    }
  ];
};
```

### Pattern 4: Manual MAC Address

Usually auto-generated, but you can specify:

```nix
myConfig.microvms.special = {
  ip = "192.168.83.50";
  mac = "02:00:00:00:00:50";  # Custom MAC
};
```

## Validation & Safety

The `microvm-host` role includes automatic validation:

### Duplicate IP Detection
```
test: microvm-config: ✗
error: Duplicate MicroVM IPs detected: 192.168.83.16
```

### Subnet Warnings
```
warning: MicroVM 'openclaw' IP 10.0.0.5 is not in 192.168.83.0/24 bridge subnet
```

## How Base + Customization Works

When you define a VM, here's what happens:

1. **flake.nix** calls `mkMicrovm "myapp" {}`
2. **mkMicrovm** builds the NixOS system with these modules (in order):
   - `microvm.nixosModules.microvm` (upstream)
   - `modules/microvm/base.nix` (shared foundation)
   - `modules/microvm/default.nix` (network adapter)
   - `targets/microvms/myapp.nix` (your customization)
3. **Host** uses `myConfig.microvms.myapp` to generate:
   - MAC address (from name)
   - Interface config
   - Shares (ro-store + cloud-init + extras)
   - Resource limits (memory, vcpus)
4. **NixOS** merges all layers into final system

## Comparison: With vs Without Base

**Without base** (old pattern):
```nix
# Every VM repeats this
environment.systemPackages = [vim git htop curl jq];
services.openssh.enable = true;
systemd.services.cloud-init = ...;
# ... 50+ lines of boilerplate
```

**With base** (new pattern):
```nix
# Just your specific needs
services.myapp.enable = true;
```

## Migration Guide

### From Old Pattern

If you have existing MicroVMs with full configuration:

1. **Keep the VM file** - it continues to work
2. **Remove redundancy** - delete duplicated base config
3. **Verify imports** - ensure `modules/microvm` is imported

### From Cloud-Init

See [Manage MicroVMs with Nix](manage-microvms-nix.md) for migrating from cloud-init YAML to pure Nix.

## Troubleshooting

### VM Won't Start

```bash
# Check host logs
journalctl -u microvm@myapp -n 100

# Validate Nix syntax
nix-instantiate --parse targets/microvms/myapp.nix

# Test build
nix build .#microvm.nixosConfigurations.myapp.config.system.build.toplevel
```

### Duplicate IP Error

```bash
# List all IPs
microvm list  # If using CLI
grep -r "ip.*=" targets/microvms/  # Check target files
grep "ip.*=" /etc/nixos/configuration.nix  # Check host config
```

### Base Changes Not Applied

All VMs must be rebuilt when base changes:

```bash
# Rebuild all MicroVMs
nix build .#microvm.nixosConfigurations.dev-vm.config.system.build.toplevel
nix build .#microvm.nixosConfigurations.openclaw.config.system.build.toplevel
# ... etc

# Or use the host to rebuild
sudo nixos-rebuild switch
```

## Best Practices

1. **DRY**: Don't repeat base config in VM files
2. **Focus**: VM files should only contain service-specific config
3. **Test**: Use `nix build` to test VMs before deploying to host
4. **Version**: Pin the base config by not changing it unexpectedly
5. **Document**: Comment VM-specific customizations

## See Also

- [Manage MicroVMs with Nix](manage-microvms-nix.md) - CLI workflow
- [Manage MicroVM Host](setup-microvm-host.md) - Host configuration
- [MicroVMs Reference](../reference/microvms.md) - Technical details
