---
title: "Architecture"
description: "Design and structure of the Nix configuration system"
type: explanation
audience: both
last-reviewed: 2026-04-06
---

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
│  Modules  │  │   Roles   │  │  Targets  │
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
├── services/         # Daemon service modules
│   ├── vllm-mlx/     # vllm-mlx inference server
│   ├── bifrost/      # Bifrost AI gateway
│   ├── caddy/        # Caddy reverse proxy
│   ├── dnsmasq/      # Local DNS resolver
│   └── vane/         # Vane AI search engine
└── nixos/            # NixOS-specific
    ├── base.nix      # Common NixOS settings
    ├── desktop.nix   # Desktop environment
    └── gaming.nix    # Gaming support
```

### Roles (What Gets Installed)

Roles are standard NixOS modules that define *package collections* grouped by purpose. Each role lives in its own file under `modules/roles/` and is gated by a `myConfig.roles.<name>.enable` option.

**Location:** `modules/roles/`

A role is a NixOS module that activates when its enable option is set:

```nix
# modules/roles/developer.nix
{ config, lib, pkgs, ... }:
let cfg = config.myConfig.roles.developer;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [emacs docker kubectl];
  };
};
```

Roles can be combined: a machine with `developer` and `creative` enabled gets packages from both.

### Services (Background Processes)

Services are launchd system daemons that run on macOS. Each service lives in `modules/services/<name>/darwin.nix`.

**Location:** `modules/services/`

**This repo uses `launchd.daemons` (system daemons), not `launchd.agents` (user agents).** System daemons:

- Start at boot, before any user logs in
- Survive logout/login cycles
- Run as a specific user via `UserName` (not root)
- Log to ephemeral `/tmp/<service>.log`


### Targets (Machine-Specific Settings)

Targets define *where* configurations apply for **artisanal** machines. Each target represents a specific machine.

**Location:** `targets/`

```
targets/
├── wweaver/          # Work laptop (artisanal)
├── MegamanX/         # Personal desktop (artisanal)
└── zero/             # NixOS gaming PC (artisanal)
```

Targets contain only machine-specific settings like hostname, hardware config, and GPU drivers.

**Disposable machines** (type-server, type-desktop) don't need targets - they use generic configurations from `machine-types/`.

## Configuration Flow

1. **Options** (`modules/common/options.nix`) define the available settings with types and defaults

2. **Modules** implement those options - when `myConfig.gaming.enable = true`, the gaming module activates

3. **Roles** select which packages and skills to include based on enabled role options

4. **Flake** composes everything for each target machine

```nix
# In flake.nix - roles are enabled via myConfig options
myConfig.roles.developer.enable = true;
myConfig.roles.desktop.enable = true;
```

## Helper Functions

The flake defines helpers to reduce boilerplate:

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

### mkMicrovm

Creates a microvm configuration for disposable NixOS virtual machines.

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

Roles can also specify platform-specific packages using conditional logic within the module.

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
- **Roles** can add packages without touching module logic
- **Targets** isolate machine-specific details

### DRY Principle

- Common configuration lives in modules, not repeated per-machine
- Helpers reduce boilerplate in flake.nix
- Roles group related packages once

### Type Safety

- Options catch configuration errors at evaluation time
- Invalid values produce clear error messages
- Defaults are documented in the option definitions
