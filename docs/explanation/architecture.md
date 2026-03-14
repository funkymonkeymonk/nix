# Architecture

This document explains the design and structure of this Nix configuration system.

## Overview

This repository manages system configurations for multiple machines using Nix Flakes. The architecture separates concerns into distinct layers:

```
┌─────────────────────────────────────────────────────────────┐
│                        flake.nix                            │
│  (Composes everything, defines machine configurations)      │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
┌───────────┐  ┌───────────┐  ┌───────────┐
│  Modules  │  │  Bundles  │  │  Targets  │
│  (how)    │  │  (what)   │  │  (where)  │
└───────────┘  └───────────┘  └───────────┘
```

## Core Concepts

### Modules (How Things Work)

Modules define *configuration logic*. They implement options and behavior but don't decide which machines use them.

**Location:** `modules/`

```
modules/
├── common/           # Shared across all systems
│   ├── options.nix   # Type-safe configuration options
│   ├── users.nix     # User management
│   └── shell.nix     # Shell configuration
├── home-manager/     # User environment (dotfiles, apps)
│   ├── development.nix
│   ├── opencode.nix
│   └── skills/       # AI agent skills
└── nixos/            # NixOS-specific
    ├── base.nix      # Common NixOS settings
    ├── desktop.nix   # Desktop environment
    └── gaming.nix    # Gaming support
```

### Bundles (What Gets Installed)

Bundles define *package collections* grouped by purpose. They're called "roles" in the configuration.

**Location:** `bundles.nix`

A role is a named collection:

```nix
developer = {
  packages = [emacs docker kubectl];
  agentSkills = ["debugging" "tdd"];
};
```

Roles can be combined: a machine with `["developer" "creative"]` gets packages from both.

### Targets (Machine-Specific Settings)

Targets define *where* configurations apply for **heirloom** machines. Each target represents a specific machine.

**Location:** `targets/`

```
targets/
├── wweaver/          # Work laptop (heirloom)
├── MegamanX/         # Personal desktop (heirloom)
└── zero/             # NixOS gaming PC (heirloom)
```

Targets contain only machine-specific settings like hostname, hardware config, and GPU drivers.

**Takeout container machines** (type-server, type-desktop) don't need targets - they use generic configurations from `machine-types/`.

## Configuration Flow

1. **Options** (`modules/common/options.nix`) define the available settings with types and defaults

2. **Modules** implement those options - when `myConfig.gaming.enable = true`, the gaming module activates

3. **Bundles** select which packages and skills to include based on roles

4. **Flake** composes everything for each target machine

```nix
# In flake.nix
"my-machine" = mkDarwinHost {
  target = ./targets/my-machine;    # Machine-specific
  roles = ["developer" "desktop"];  # Bundles to include
  user = mkUser "name" "email";     # User configuration
};
```

## Helper Functions

The flake defines helpers to reduce boilerplate:

### mkDarwinHost / mkNixosHost

Creates a complete machine configuration from minimal inputs:

```nix
mkDarwinHost {
  target = ./targets/my-machine;
  user = mkUser "username" "email@example.com";
  roles = ["developer" "desktop"];
  extraConfig = { gaming.enable = true; };
  extraModules = [];
}
```

### mkUser

Creates user configuration with common defaults:

```nix
mkUser "username" "email@example.com"
# Returns:
# {
#   users = [{ name = "username"; email = "..."; ... }];
#   development.enable = true;
#   onepassword.enable = true;
#   # ... other defaults
# }
```

### mkBundleModule

Transforms a list of roles into a complete module with packages and configuration:

```nix
mkBundleModule "darwin" ["developer" "desktop"]
```

## Option System

The `myConfig` namespace provides type-safe configuration:

```nix
# Defining an option
myConfig.gaming.enable = mkEnableOption "gaming support";

# Using an option
config = mkIf cfg.gaming.enable {
  programs.steam.enable = true;
};
```

Options are defined in `modules/common/options.nix` and implemented by various modules.

## Heirloom Dishes vs Takeout Containers

The flake supports two approaches to machine management:

### Heirloom Dishes (Traditional)

Each machine is unique, hand-crafted, named, and cared for individually:
- Hostname defined in the flake (`networking.hostName`)
- Per-machine `targets/<hostname>/` directory
- Hardware-specific settings
- Impure builds (references local paths like `/etc/nixos/`)
- If it breaks, you repair it

**Examples**: `wweaver`, `MegamanX`, `zero`

### Takeout Containers (Disposable)

Machines are standardized, disposable, and interchangeable:
- Hostname from DHCP (not in flake)
- No per-machine directories
- Generic machine types (`type-server`, `type-desktop`)
- Pure builds (everything from GitHub)
- Auto-upgrading from flake
- If one has a problem, throw it away and grab another

**Benefits**:
- ✅ Build anywhere (CI, different machines)
- ✅ No `hardware-configuration.nix` per machine
- ✅ Faster deployment (5 min vs 30 min)
- ✅ True infrastructure-as-code
- ✅ You don't care which specific one you get

### When to Use Which

| Use Case | Pattern | Example |
|----------|---------|---------|
| Headless servers | Takeout Container | `type-server` |
| MicroVM hosts | Takeout Container | `type-server` |
| Gaming workstation | Heirloom | `zero` |
| Work laptop | Heirloom | `wweaver` |
| Desktop with unique GPU | Heirloom | Custom target |

## Platform Handling

The system supports both macOS (Darwin) and Linux (NixOS):

```nix
# Platform detection
myConfig.isDarwin  # true on macOS

# Platform-specific code in modules
config = mkIf (!config.myConfig.isDarwin) {
  # NixOS-only configuration
};
```

Bundles can also specify platform-specific packages via the `platforms` attribute.

## Agent Skills System

Skills are AI assistant instructions managed through Nix:

1. Skills are defined in `modules/home-manager/skills/manifest.nix`
2. Each skill is assigned to roles
3. When a role is enabled, its skills are installed
4. Skills are symlinked to `~/.config/opencode/skills/`

This ensures consistent skill availability across all your machines.

## Why This Design?

### Separation of Concerns

- **Modules** can be modified without changing machine configs
- **Bundles** can add packages without touching module logic
- **Targets** isolate machine-specific details

### DRY Principle

- Common configuration lives in modules, not repeated per-machine
- Helpers reduce boilerplate in flake.nix
- Roles bundle related packages once

### Type Safety

- Options catch configuration errors at evaluation time
- Invalid values produce clear error messages
- Defaults are documented in the option definitions
