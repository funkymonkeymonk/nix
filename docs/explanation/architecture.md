# Architecture Overview

This document explains the architecture of this Nix configuration system and the reasoning behind its design.

## Core Concepts

### Declarative Configuration

Unlike traditional configuration management where you run commands to change state, this system defines the desired state declaratively. Nix then computes what changes are needed to reach that state.

This approach provides:
- **Reproducibility**: The same configuration produces identical results
- **Rollback**: Previous configurations are preserved and can be restored
- **Atomic updates**: Changes apply completely or not at all

### Flakes

Nix Flakes provide a standardized way to define Nix projects with:
- **Locked dependencies**: `flake.lock` pins exact versions
- **Composability**: Flakes can reference other flakes
- **Standard interface**: Predictable structure across projects

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        flake.nix                            │
│                    (orchestrates everything)                │
└─────────────────────────┬───────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │ Modules  │    │ Bundles  │    │ Targets  │
    │  (how)   │    │  (what)  │    │ (where)  │
    └──────────┘    └──────────┘    └──────────┘
```

### Modules (How Things Work)

Modules define configuration logic - how features are implemented. They:
- Accept options as input
- Produce configuration as output
- Can be composed and reused

Example: The shell module configures zsh, aliases, and environment variables based on options.

### Bundles (What Gets Installed)

Bundles group packages and settings by purpose. Roles like `developer` or `creative` are bundles that define:
- Which packages to install
- What configurations to enable
- Which skills to make available

This separation means you can change what a "developer" setup includes without changing how packages are installed.

### Targets (Where It Applies)

Targets are machine-specific configurations. Each target:
- Specifies hardware and platform
- Selects which bundles to apply
- Provides machine-specific overrides

## Configuration Flow

```
1. User defines roles in flake.nix
        │
        ▼
2. mkBundleModule collects packages from bundles.nix
        │
        ▼
3. Modules process options and produce configurations
        │
        ▼
4. Platform-specific modules (darwin.nix or nixos.nix) apply
        │
        ▼
5. Home-manager manages user environment
        │
        ▼
6. Final configuration is built and activated
```

## Separation of Concerns

### Why Separate Modules from Bundles?

**Modules** answer: "How do I configure X?"
**Bundles** answer: "What should this role include?"

This separation allows:
- Reusing module logic across different bundle combinations
- Changing bundle contents without modifying implementation
- Testing modules independently

### Why Separate Targets from Bundles?

**Targets** answer: "What's special about this machine?"
**Bundles** answer: "What does this role need?"

A target like `wweaver` might use the `developer` bundle but with machine-specific hardware settings.

## Home-Manager Integration

Home-manager handles user-level configuration:
- Dotfiles and application configs
- User packages (separate from system packages)
- Session environment

This allows multiple users on the same machine to have different configurations.

## Cross-Platform Design

The system supports both macOS (nix-darwin) and Linux (NixOS):

- **Common modules**: Shared across platforms
- **Platform modules**: `os/darwin.nix` and `os/nixos.nix`
- **Platform-specific packages**: Defined per-role in bundles

The `myConfig.isDarwin` option enables conditional logic when platform differences require it.

## Why This Architecture?

### Alternatives Considered

**Single monolithic configuration:**
- Simpler but doesn't scale
- Hard to share subsets of configuration
- Difficult to test pieces independently

**Per-machine configurations:**
- Maximum flexibility
- Lots of duplication
- Hard to keep machines consistent

### Benefits of This Approach

1. **DRY (Don't Repeat Yourself)**: Common logic lives in modules
2. **Composable**: Mix and match bundles as needed
3. **Testable**: Validate configurations before applying
4. **Discoverable**: Clear structure for finding settings
5. **Maintainable**: Changes propagate automatically

## Trade-offs

**Complexity**: More files and indirection than a simple config.nix
**Learning curve**: Need to understand modules, bundles, targets
**Build time**: Full evaluation on changes (mitigated by caching)

These trade-offs are worthwhile for a configuration system managing multiple machines with shared requirements.
