# NixOS Flake Installer

Interactive TUI installer for deploying NixOS systems from the funkymonkeymonk/nix flake.
Built with TypeScript, React, Ink, and Bun.

## Usage

### From GitHub (Fresh NixOS Live USB)

```bash
sudo nix run --extra-experimental-features "flakes nix-command" github:funkymonkeymonk/nix#installer
```

### From Specific Branch

```bash
sudo nix run --extra-experimental-features "flakes nix-command" github:funkymonkeymonk/nix/BRANCH#installer
```

### Enable Experimental Features Permanently

Add to `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

Then you can run without the flag:

```bash
sudo nix run github:funkymonkeymonk/nix#installer
```

## Testing on macOS

Since this is a Linux-only installer, you can test the build without running it:

### Option 1: Build Only (No Execution)

```bash
# Build the package for Linux (won't run on macOS, but validates it builds)
nix build .#installer --dry-run

# Or build and check the output
nix build .#installer
ls -la result/bin/
```

### Option 2: Check Flake Syntax

```bash
nix flake check
```

### Option 3: Test in NixOS VM

```bash
# Build a NixOS VM for testing
nix build .#nixosConfigurations.test-vm.config.system.build.vm
./result/bin/run-nixos-vm
```

Then inside the VM:

```bash
sudo nix run --extra-experimental-features "flakes nix-command" github:funkymonkeymonk/nix#installer
```

### Option 4: Docker Container

```bash
# Run a NixOS container
docker run -it --privileged nixos/nix:latest

# Inside container
sudo nix run --extra-experimental-features "flakes nix-command" github:funkymonkeymonk/nix#installer
```

## Development

### Local Development with Bun

```bash
cd packages/installer

# Install dependencies
bun install

# Run directly
bun run src/index.tsx

# Build
bun run build
```

### Project Structure

```
packages/installer/
├── src/
│   └── index.tsx       # Main React/Ink TUI application
├── package.json        # Bun dependencies
├── tsconfig.json       # TypeScript configuration
├── default.nix         # Nix package definition
└── README.md           # This file
```

## Features

- Beautiful TUI with Ink (React for CLI)
- Interactive hostname input
- Admin user picker (arrow keys)
- Target existence detection
- Live USB and existing system modes
- Real-time installation progress

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑/k` | Move up (user selection) |
| `↓/j` | Move down (user selection) |
| `Enter` | Confirm / Continue |
| `q` / `Ctrl+C` | Quit |

## Tech Stack

- **Runtime**: Bun (fast JavaScript runtime)
- **UI Framework**: React + Ink (React for CLI)
- **Language**: TypeScript
- **Build**: Nix + Bun bundler
