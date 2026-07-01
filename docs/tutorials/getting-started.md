---
title: "Getting Started"
description: "Overview of this Nix configuration system and your first steps"
type: tutorial
audience: both
last-reviewed: 2026-06-30
---

# Getting Started

In this tutorial you will learn what this repository is, see its structure, and set up the development environment. By the end, you will be able to evaluate configurations and run local tests.

## What This Is

This repository manages the configuration of multiple machines through a single Nix flake. It supports both macOS (nix-darwin) and NixOS.

The repo follows three patterns:

| Pattern | When to Use | Example |
|---------|-------------|---------|
| **Heirloom** | Unique machine with custom settings | Work laptop, gaming desktop |
| **Takeout Container** | Standardized, replaceable machines | Headless servers, MicroVM hosts |
| **MicroVM** | Lightweight isolated NixOS VMs | AI tooling, dev environments |

## Repository Structure at a Glance

```
├── modules/                 # Reusable configuration logic
│   ├── common/              # Shared options and user management
│   ├── home-manager/        # User environment (dotfiles, apps)
│   ├── roles/               # Role modules (package bundles)
│   ├── services/            # Background service definitions
│   ├── microvm/             # MicroVM guest configuration
│   └── nixos/              # NixOS-specific modules
├── targets/                 # Machine-specific configurations
│   ├── wweaver/             # Work laptop (macOS)
│   ├── MegamanX/            # Personal desktop (macOS)
│   ├── zero/                # Gaming PC (NixOS)
│   └── microvms/            # MicroVM definitions
├── machine-types/           # Generic configurations (type-server, type-desktop)
├── disk-configs/            # Disko disk layouts
├── os/                      # Platform-specific base configuration
├── library/                 # System-building abstractions
└── flake.nix               # Composes everything together
```

## Core Concepts

**Roles** group packages by purpose. A machine enables one or more roles:

- `developer` — emacs, helix, docker, kubectl, python, nodejs
- `creative` — ffmpeg, imagemagick, pandoc
- `gaming` — Steam, Moonlight game streaming
- `opencode` / `claude` / `pi` — AI coding agents
- And more (see [Roles Reference](../reference/roles.md))

**Targets** hold machine-specific settings in `targets/<name>/`. Heirloom machines have their own target directory; takeout container machines use one of the generic configurations under `machine-types/`.

## Prerequisites

- macOS 14+ (Apple Silicon) **or** a NixOS-capable machine
- Terminal access with administrator privileges
- A GitHub account with SSH key configured

## Step 1: Install Nix

Use the Determinate Systems installer if Nix is not already installed:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Restart your terminal and verify:

```bash
nix --version
# Expected: nix (Nix) 2.x.x or later
```

## Step 2: Clone the Repository

```bash
git clone git@github.com:funkymonkeymonk/nix.git ~/nix
cd ~/nix
```

## Step 3: Enter the Development Shell

```bash
devenv shell
```

This provides access to all development tools (linters, formatters, devenv tasks). The first invocation downloads and caches dependencies.

You can also use `nix develop` without the devenv wrapper:

```bash
nix develop
devenv tasks list
```

## Step 4: Check What Configurations Are Available

List macOS configurations:

```bash
nix flake show | grep darwinConfigurations
```

List NixOS configurations:

```bash
nix flake show | grep nixosConfigurations
```

Expected output includes entries like `wweaver`, `MegamanX`, `type-server`, and `zero`.

## Step 5: Run Local Validation

Before building or applying anything, verify the flake evaluates cleanly:

```bash
# Fast lint check (formatting, dead code)
devenv tasks run check:lint

# Eval test for your platform
devenv tasks run test:darwin-eval    # on macOS
devenv tasks run test:nixos-eval     # on Linux
```

If both pass, the flake is healthy.

## What's Next?

Continue with your platform's setup walkthrough: [Set Up Your Mac](setup-your-mac.md) or [Set Up Your NixOS Machine](setup-your-nixos-machine.md).

If you want to understand how modules and roles fit together before configuring anything, read [Architecture](../explanation/architecture.md).

## Troubleshooting

### "experimental-features" error

Add this to `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

The Determinate installer usually sets this automatically.

### Flake evaluation fails with missing input locks

Unlock the flake:

```bash
nix flake update
```

Then re-run the failing command.

### devenv tasks are not found

Ensure you are in the development shell (`devenv shell` or `nix develop`) before running devenv tasks. Tasks defined in `devenv.nix` are only available inside the dev environment.
