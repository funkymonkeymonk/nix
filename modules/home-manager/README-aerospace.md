# AeroSpace Window Manager Module

This module provides a comprehensive AeroSpace tiling window manager configuration for macOS systems.

## Overview

The AeroSpace module configures a sophisticated 3-section workspace layout optimized for productivity, with automatic window placement rules and multi-monitor support.

## Features

- **3-section horizontal layout**: Left tiles, middle accordion, right tiles
- **Vim-style navigation**: hjkl keys for window focus and movement
- **Automatic window placement**: Apps automatically move to designated workspaces
- **Multi-monitor support**: Workspace-to-monitor assignments
- **Extensive keybindings**: Comprehensive keyboard shortcuts for all operations

## Configuration

The module is located at `modules/home-manager/aerospace.nix` and is automatically imported in the Darwin flake configurations.

### Key Components

- **Startup Layout**: Automatically creates 3-section workspace on launch
- **Window Detection**: Moves specific applications to designated workspaces
- **Monitor Assignment**: Ensures consistent workspace placement across displays
- **Keybindings**: Extensive keyboard shortcuts using `shift-ctrl-alt` modifier

### Automatic Window Placement

- **Discord & Spark Mail** → Workspace 2 (Comms)
- **Deezer & Logseq** → Workspace 3 (Dash)
- **All other apps** → Primary section (middle) by default

## Usage

The module is enabled by default in Darwin configurations. To customize:

1. Edit `modules/home-manager/aerospace.nix`
2. Test with `task test`
3. Apply with `task build` or `task switch`

## Keybindings Reference

See the main [AeroSpace README](../../README-aerospace.md) for complete keybindings documentation.

## Integration

This module integrates with:
- **home-manager**: User-specific configuration management
- **Nix Flakes**: Declarative system configuration
- **Multi-monitor setups**: Automatic workspace distribution