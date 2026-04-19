---
title: "Manage MicroVMs with Nix"
description: "Use the microvm CLI to manage MicroVM definitions in pure Nix format instead of fragile YAML."
type: how-to
audience: user
last-reviewed: 2026-04-18
---

# Manage MicroVMs with Nix

This guide shows you how to use the `microvm` CLI tool to manage MicroVM definitions in pure Nix format. This replaces the legacy cloud-init YAML approach with type-safe, validated Nix expressions.

## Overview

The `microvm` command generates proper Nix syntax that integrates directly with your NixOS configuration. Benefits include:

- **Type safety**: Nix evaluation catches errors before they reach runtime
- **No fragile parsing**: Direct Nix generation instead of regex-based YAML parsing
- **Native integration**: Works with `nixos-rebuild switch` like any other Nix config
- **Version control friendly**: Standard Nix files that can be tracked in git

## Quick Start

```bash
# 1. Initialize microvm configuration (creates /etc/nixos/microvms.nix)
sudo microvm init

# 2. Add your first MicroVM
sudo microvm add openclaw --ip 192.168.83.16

# 3. Verify it was added
microvm list

# 4. Validate the Nix syntax
sudo microvm generate

# 5. Apply the configuration
sudo nixos-rebuild switch
```

## Commands

### `microvm init`

Creates the initial `/etc/nixos/microvms.nix` file with a template structure.

```bash
sudo microvm init
```

This creates a file with:
- `microvm.vms` attribute for VM definitions
- Helper functions for MAC address generation
- Cloud-init integration for per-VM hostname configuration

### `microvm add <name> [options]`

Adds a new MicroVM definition to the configuration.

**Basic usage:**
```bash
# Add with full IP
sudo microvm add matrix --ip 192.168.83.15

# Add with just the last octet (expands to 192.168.83.20)
sudo microvm add myapp --ip 20

# Add with automatic IP assignment
sudo microvm add openclaw
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--ip <ip>` | IP address or last octet | Auto-assigned |
| `--flake <flake>` | Full flake reference | `.#microvm.nixosConfigurations.<name>` |
| `--mac <mac>` | Custom MAC address | Auto-generated from name |
| `--no-autostart` | Don't start on boot | Autostart enabled |
| `--memory <mb>` | Memory in MB | 1024 |
| `--vcpus <n>` | Number of vCPUs | 2 |

**Examples:**

```bash
# External flake reference
sudo microvm add myapp \
  --ip 25 \
  --flake github:user/repo#microvm.nixosConfigurations.myapp

# Custom MAC and disabled autostart
sudo microvm add test-vm \
  --ip 30 \
  --mac 02:00:00:00:00:30 \
  --no-autostart
```

### `microvm list`

Lists all defined MicroVMs with their configuration.

```bash
microvm list
```

Output:
```
NAME                 MAC             FLAKE                                    AUTOSTART
----                 ---             -----                                    ---------
openclaw             02:42:8c:6d:5a  .#microvm.nixosConfigurations.openclaw   yes
matrix               02:5f:3b:9c:1d  .#microvm.nixosConfigurations.matrix     yes
```

### `microvm remove <name>`

Removes a MicroVM definition (creates a backup first).

```bash
sudo microvm remove openclaw
```

### `microvm generate`

Validates the Nix syntax and shows a preview of the generated configuration.

```bash
sudo microvm generate
```

### `microvm edit <name>`

Shows the current configuration for a MicroVM (use your editor to modify).

```bash
sudo microvm edit openclaw
# Output shows the Nix block for that VM
# Edit with: sudo nano /etc/nixos/microvms.nix
```

## Configuration File

The `microvm` command manages `/etc/nixos/microvms.nix`:

```nix
# /etc/nixos/microvms.nix - Managed by 'microvm' command
{ config, lib, pkgs, ... }:
let
  cloudInitDir = "/var/lib/microvms/cloud-init";
  
  # Helper to generate MAC from name
  mkMac = name: let
    hash = builtins.substring 0 10 (builtins.hashString "sha256" name);
    # ... implementation
  in "02:...";
in {
  microvm.vms = {
    openclaw = {
      flake = ".#microvm.nixosConfigurations.openclaw";
      interfaces = [{
        type = "tap";
        id = "microvm-openclaw";
        mac = "02:42:8c:6d:5a:f8";
      }];
      hypervisor = pkgs.cloud-hypervisor;
      writableStoreOverlay = "/nix/.rw-store";
      shares = [
        { tag = "ro-store"; source = "/nix/store"; mountPoint = "/nix/.ro-store"; proto = "virtiofs"; }
        { tag = "cloud-init"; source = cloudInitDir; mountPoint = "/etc/cloud-init"; proto = "virtiofs"; }
      ];
      autostart = true;
    };
    # ... more VMs
  };
  
  # Per-VM cloud-init files (generated from VM names)
  environment.etc = lib.mkIf (config.microvm.vms != {}) (
    lib.mapAttrs' (name: vm: {
      name = "cloud-init/${name}.yaml";
      value = {
        text = ''
          #cloud-config
          hostname: ${name}
        '';
        mode = "0644";
      };
    }) config.microvm.vms
  );
}
```

## Integration

### Automatic Import

If you're using the `microvm-host` role, the `/etc/nixos/microvms.nix` file is automatically imported when it exists:

```nix
# In your configuration.nix or machine type
{
  myConfig.roles.microvm-host.enable = true;
  # Automatically imports /etc/nixos/microvms.nix if it exists
}
```

### Manual Import

If not using the role, import it manually:

```nix
# /etc/nixos/configuration.nix
{
  imports = [
    # ... other imports
    /etc/nixos/microvms.nix
  ];
}
```

## Workflow

### Adding a New MicroVM

1. **Create VM target file** in your flake:
   ```bash
   # Create targets/microvms/my-new-vm.nix
   # Define the MicroVM configuration
   ```

2. **Add VM to flake** (if not using `.#microvm.nixosConfigurations.<name>`):
   ```nix
   # In flake.nix
   microvm.nixosConfigurations.my-new-vm = mkMicrovm "my-new-vm" {
     roles.llm-host.enable = true;
   };
   ```

3. **Add to host**:
   ```bash
   sudo microvm add my-new-vm --ip 192.168.83.25
   ```

4. **Apply**:
   ```bash
   sudo nixos-rebuild switch
   ```

### Removing a MicroVM

```bash
# Remove from host configuration
sudo microvm remove my-old-vm

# Apply
sudo nixos-rebuild switch

# Optionally remove from flake
# Edit flake.nix to remove the microvm.nixosConfigurations entry
```

## Migration from Cloud-Init

If you're currently using the cloud-init YAML approach:

1. **List existing VMs** from cloud-init:
   ```bash
   sudo nix-cloud-init microvm list
   ```

2. **Initialize new system**:
   ```bash
   sudo microvm init
   ```

3. **Migrate each VM**:
   ```bash
   # For each VM, add it to the new system
   sudo microvm add <name> --ip <ip>
   ```

4. **Disable old cloud-init**:
   Remove `nix.roles = [ "microvm-host" ]` from `/etc/cloud-init.yaml` or delete the file.

5. **Apply**:
   ```bash
   sudo nixos-rebuild switch
   ```

## Troubleshooting

### "Invalid Nix syntax"

```bash
# Validate the file
nix-instantiate --parse /etc/nixos/microvms.nix

# Check for issues
sudo microvm generate
```

### "MicroVM not found"

```bash
# List to verify
microvm list

# Check if in file
grep "my-vm" /etc/nixos/microvms.nix
```

### Backup and Restore

The `microvm` command creates backups automatically:

```bash
# List backups
ls -la /etc/nixos/microvms.nix.backup.*

# Restore from backup
sudo cp /etc/nixos/microvms.nix.backup.20250418000000 /etc/nixos/microvms.nix
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MICROVM_NIX_FILE` | Path to microvm.nix file | `/etc/nixos/microvms.nix` |
| `MICROVM_DEBUG` | Enable debug output | `0` |

## Comparison: Cloud-Init vs Nix-Native

| Feature | Cloud-Init YAML | Nix-Native (microvm CLI) |
|---------|-----------------|--------------------------|
| Format | YAML | Nix expressions |
| Validation | Runtime regex parsing | Nix evaluation |
| Type safety | No | Yes (Nix catches errors) |
| Integration | Activation scripts | Standard imports |
| Editing | Text manipulation | Structured generation |
| Backups | Manual | Automatic |
| Dependencies | `gum`, bash | Just nix |

## See Also

- [MicroVM Host Setup](setup-microvm-host.md) - Configure a host for MicroVMs
- [MicroVMs Reference](../reference/microvms.md) - Technical details about MicroVMs
- [Cloud-init Format](../reference/cloud-init-format.md) - Legacy YAML format (deprecated)
