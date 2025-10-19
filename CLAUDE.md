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

## Branch-before-main workflow

This repository follows a "branch-before-main" workflow for assistant-made changes. Assistants working on this repo should follow these rules and prompt the repository owner before modifying `main`.

1. Proposal before main
   1. Before making any code change that would commit to or otherwise modify the `main` branch (except pulling/merging `main` locally), the assistant will propose creating a new branch and offer to create it.
   2. The assistant will wait for the user's explicit approval before creating the branch or committing changes that would affect `main`.

2. Branch creation and commits
   1. If approved, the assistant will create the branch and perform commits there.
   2. By default the assistant will create the branch locally and will not push to `origin` unless the user explicitly asks.

3. Push and PR behavior
   1. The assistant will not push to `origin` by default — it will ask before pushing any branch.
   2. The assistant will not open a pull request by default — it will ask before creating one.
   3. If the user requests a PR, the assistant will create a draft PR by default.

4. Branch naming
   1. The assistant will check the repository for a consistent branch naming pattern. If a clear pattern exists, the assistant will show that pattern and prompt the user for a branch name that follows it.
   2. If no consistent pattern exists, the assistant will follow the Conventional Branch Naming scheme (https://conventional-branch.github.io/about/) and propose a name accordingly (for docs changes use the `docs/` type).
   3. Example branch name for this change: `docs/assistant-branch-policy`.

5. Changing main
   1. The assistant will only modify `main` if the user explicitly instructs it to do so.

6. Transparency
   1. When proposing a branch the assistant will include the exact commands it will run and the commit message it plans to use, and will wait for the user's approval.

These are workflow preferences only — they do not change repository code or CI behavior.

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
