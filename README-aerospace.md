# AeroSpace Window Manager Configuration

This document describes the AeroSpace tiling window manager configuration used in this Nix Flakes setup.

## Overview

AeroSpace is a tiling window manager for macOS that provides efficient window management through keyboard-driven workflows. This configuration creates a sophisticated 3-section workspace layout optimized for productivity.

## Core Features

### Service Configuration
- **Package**: Uses `pkgs.unstable.aerospace` for the latest features
- **Gaps**: Zero gaps between windows for maximum screen real estate
- **Layout**: 3-section horizontal workspace with specialized layouts per section

### Startup Layout
The `after-startup-command` automatically configures a 3-section horizontal layout:

1. **Left Section** (Secondary 1): Tiles layout - windows stack vertically
2. **Middle Section** (Primary): Accordion layout - windows expand to fill available space
3. **Right Section** (Secondary 2): Tiles layout - windows stack vertically

## Keybindings

All keybindings use the `shift-ctrl-alt` modifier combination for consistency.

### Window Navigation
- `shift-ctrl-alt-h/j/k/l` - Focus windows (vim-style: left/down/up/right)
- `shift-ctrl-alt-y/u/i/o` - Swap windows with focus
- `shift-ctrl-alt-n/m/,/.` - Move windows in cardinal directions

### Layout Management
- `shift-ctrl-alt-left/down/up/right` - Join windows in different directions
- `shift-ctrl-alt-p` - Increase window size (+200px)
- `shift-ctrl-alt-/` - Decrease window size (-200px)
- `shift-ctrl-alt-'` - Balance all window sizes

### Section Navigation
- `shift-ctrl-alt-1` - Jump to left section (Secondary 1)
- `shift-ctrl-alt-2` - Jump to middle section (Primary/Accordion)
- `shift-ctrl-alt-3` - Jump to right section (Secondary 2)
- `shift-ctrl-alt-r` - Reset all section layouts to defaults
- `shift-ctrl-alt-t` - Full layout refresh (recreate 3-section startup layout)

### Workspace Management
- `shift-ctrl-alt-4` - Move window to previous workspace
- `shift-ctrl-alt-5` - Switch to previous workspace
- `shift-ctrl-alt-6` - Switch to next workspace
- `shift-ctrl-alt-=` - Move window to next workspace

## Automatic Window Placement

The configuration includes rules that automatically move specific applications to designated workspaces:

### Communication Apps → Workspace 2 (Comms)
- **Discord** (`com.hnc.Discord`)
- **Spark Mail** (`com.readdle.smartemail-Mac`)

### Dashboard Apps → Workspace 3 (Dash)
- **Deezer** (`com.deezer.deezer-desktop`)
- **Logseq** (`com.electron.logseq`)

## Multi-Monitor Support

Workspace-to-monitor assignments ensure consistent placement across multiple displays:

- **1.Main**: Primary monitor only
- **2.Comms**: Monitors 1 or 3 (prefers external displays)
- **3.Dash**: Monitors 3 or 1 (prefers external displays)
- **4.Distracted**: Primary monitor only

## Usage Tips

### Getting Started
1. AeroSpace starts automatically with the system
2. New windows appear in the primary (middle) section by default
3. Use `shift-ctrl-alt-1/2/3` to navigate between sections

### Layout Philosophy
- **Left/Right Sections**: Use tiles layout for consistent, predictable window sizing
- **Middle Section**: Uses accordion layout for flexible, adaptive window sizing
- **Communication apps**: Isolated to prevent distractions during focused work
- **Dashboard apps**: Grouped for quick access to productivity tools

### Customization
To modify this configuration:
1. Edit `aerospace.nix` in the repository root
2. Test changes with `task test`
3. Apply with `task build` or `task switch`

## Integration with Nix Flakes

This configuration integrates with the broader Nix Flakes setup:
- Managed through `home-manager` for user-specific configuration
- Version controlled alongside other system configurations
- Tested via CI/CD pipeline for configuration validity
- Formatted automatically with alejandra

## Troubleshooting

### Common Issues
- **Windows not moving**: Check that AeroSpace is running (`ps aux | grep aerospace`)
- **Keybindings not working**: Verify modifier keys are pressed simultaneously
- **Layout not applying**: Run `aerospace reload-config` after configuration changes

### Reset Layout
- Use `shift-ctrl-alt-r` to reset all sections to their default layouts if things get disorganized
- Use `shift-ctrl-alt-t` for a complete layout refresh that recreates the original 3-section startup layout