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

## Assistant list-formatting preference

This repository includes a preferred assistant behavior for rendering option lists when interacting about this project. When an assistant provides lists of options, it should render them as Markdown lists following these rules:

1. For 1–9 options: use a numbered Markdown list (`1.`, `2.`, …).
2. For 10–20 options: use a lowercase-letter Markdown list (`a.`, `b.`, …).
3. For more than 20 options: group the options into the fewest distinct categories necessary and use a dotted numeric nesting scheme for groups and items (for example, `1.`, `1.1`, `1.2`, `2.`, ...).
4. Put the index only at the start of each option; do not include additional parenthetical shorthand.
5. For lists with more than 20 items, attempt to minimize the number of top-level groups.

## Retrospection

- When the user tells the assistant that are done offer to do a retrospective of the conversation.
- Review the conversation and offer suggestions on the following improvement areas:
  - Misundersandings during agent interaction
  - Formatting errors
  - Agent cost optimization
  - Wall clock time optimization
- Changes should be proposed with a bias to the lowest estimated difficulty of the change and then following order:
  - Agent behavior
    - Should be expressed as concise changes to CLAUDE.md if possible.
    - Explain the changes.
    - Offer to make them and commit them.
  - Tool requests
    - Should be expressed as a prompt that the user can use to search for or create a tool to fulfill the need.
  - User behavior
    - Should be expressed as requests from the assistant to the user.
