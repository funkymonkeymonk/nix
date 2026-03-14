# Add a New Machine

This guide shows you how to add a new machine configuration to the flake.

## Quick Decision: Heirloom vs Takeout Container

**Use Takeout Containers (type-*) for:**
- Servers that should be identical
- Machines where hostname doesn't matter in config
- Headless servers, MicroVM hosts
- Any machine using DHCP for hostname

**Use Heirloom Dishes (named targets) for:**
- Workstations with unique configurations
- Gaming machines with specific GPU setups
- Laptops with user-specific settings
- When you need `networking.hostName` in the flake

## For Takeout Containers (Recommended for Servers)

Just use the existing `type-server` or `type-desktop` configurations:

```bash
# Install using takeout container pattern
nixos-install --flake github:funkymonkeymonk/nix#type-server

# Hostname comes from DHCP - no per-machine config needed!
```

The `type-server` configuration includes:
- MicroVM host support (qemu, virtiofsd)
- Auto-upgrade from GitHub daily
- Hardened SSH (keys only, no root)
- Firewall with SSH access

See [DISPOSABLE.md](../../DISPOSABLE.md) for full details.

## For macOS (Darwin)

### Step 1: Create Target Directory

```bash
mkdir -p targets/my-machine
```

### Step 2: Create Target Configuration

Create `targets/my-machine/default.nix`:

```nix
# my-machine target configuration
_: {
  # Machine-specific settings go here
  # Most config comes from roles and mkUser
}
```

### Step 3: Add to flake.nix

Add your machine to `darwinConfigurations`:

```nix
"my-machine" = mkDarwinHost {
  target = ./targets/my-machine;
  user = mkUser "username" "email@example.com";
  roles = ["developer" "desktop" "llm-client"];
};
```

### Step 4: Build and Apply

```bash
nix build .#darwinConfigurations.my-machine.system
./result/sw/bin/darwin-rebuild switch --flake .#my-machine
```

## For NixOS

### Option A: Takeout Container Pattern (Servers)

For headless servers or MicroVM hosts, use `type-server`:

```bash
# Install directly - no per-machine configuration needed
nixos-install --flake github:funkymonkeymonk/nix#type-server

# Or if installing from local flake:
nixos-install --flake .#type-server
```

The hostname is assigned via DHCP. No `targets/` directory needed!

### Option B: Heirloom Pattern (Workstations)

For gaming rigs, workstations, or machines needing unique config:

#### Step 1: Create Target Directory

```bash
mkdir -p targets/my-nixos
```

#### Step 2: Generate Hardware Configuration

On the NixOS machine:

```bash
nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

Copy this file to `targets/my-nixos/hardware-configuration.nix`.

#### Step 3: Create Target Configuration

Create `targets/my-nixos/default.nix`:

```nix
{config, pkgs, ...}: {
  imports = [./hardware-configuration.nix];

  networking.hostName = "my-nixos";
  networking.networkmanager.enable = true;
  time.timeZone = "America/New_York";

  # Add machine-specific packages
  environment.systemPackages = with pkgs; [
    vim
    wget
  ];
}
```

#### Step 4: Add to flake.nix

Add your machine to `nixosConfigurations`:

```nix
"my-nixos" = mkNixosHost {
  target = ./targets/my-nixos;
  user = mkUser "username" "email@example.com";
  roles = ["developer" "desktop"];
};
```

#### Step 5: Build and Apply

```bash
sudo nixos-rebuild switch --flake .#my-nixos
```

## Customizing Your Configuration

### Enable Additional Features

Use `extraConfig` for machine-specific settings:

```nix
"my-machine" = mkDarwinHost {
  target = ./targets/my-machine;
  user = mkUser "username" "email@example.com";
  roles = ["developer"];
  extraConfig = {
    desktop.enable = true;
    gaming.enable = true;
  };
};
```

### Add Extra Modules

Use `extraModules` to include additional nix modules:

```nix
"my-machine" = mkDarwinHost {
  # ...
  extraModules = [
    mac-app-util.darwinModules.default
  ];
};
```

## Validation

After adding your configuration, validate it:

```bash
# Quick syntax check
devenv tasks run check:lint

# Full validation
devenv tasks run check:all
```

> **See also:** [Roles Reference](../reference/roles.md) for available role options
