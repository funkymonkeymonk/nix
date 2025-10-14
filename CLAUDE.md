# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a personal macOS system configuration using Nix Flakes, nix-darwin, and home-manager. It manages system packages, homebrew applications, dotfiles, and various system configurations across multiple machines.

## Common Development Commands

Use the `task` command (go-task) for all operations:

- `task` or `task list` - List all available tasks
- `task build` or `task switch` - Apply system configuration (runs `darwin-rebuild switch --flake ./`)  
- `task test` - Run nix flake check to validate configuration
- `task fmt` - Format all Nix files using alejandra formatter
- `task init` - Initial setup for first-time installation

## Architecture Overview

### Core Files
- `flake.nix` - Main flake definition with system configurations for two machines: "Will-Stride-MBP" and "MegamanX"
- `home.nix` - Home-manager configuration (user-level packages, shell aliases, dotfiles)
- `homebrew.nix` - Homebrew cask definitions for GUI applications
- `aerospace.nix` - AeroSpace window manager configuration

### System Structure
The flake defines two darwinConfigurations:
1. **Will-Stride-MBP** - Basic configuration for user "willweaver"  
2. **MegamanX** - Extended configuration for user "monkey" with additional maker/entertainment apps

### Package Management Strategy
- **Nix packages**: Core CLI tools and development utilities (defined in flake.nix environment.systemPackages)
- **Homebrew casks**: GUI applications that aren't well-supported in Nix on macOS
- **Home-manager**: User-specific configurations and packages

### Key Components
- Uses unstable nixpkgs overlay for newer packages (accessed as `pkgs.unstable`)
- Integrates 1Password for secret management
- Configures git, zsh, emacs, alacritty, and other development tools
- Sets up AeroSpace tiling window manager with custom keybindings
- Includes Docker utilities and custom shell functions

## Development Environment

The project uses devenv for development tooling:
- Pre-commit hook with alejandra formatter enabled
- Git integration for formatting validation

## Testing and Validation

Always run `task test` (nix flake check) before applying changes to validate the configuration. The formatter (`task fmt`) should be run before commits to maintain code style consistency.