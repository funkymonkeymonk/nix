---
title: "Set Up a New Mac"
description: "Configure a new macOS system using this Nix flake"
type: how-to
audience: both
automation-ready: false
last-reviewed: 2026-04-11
---

# Set Up a New Mac

This guide shows you how to configure a new macOS system using the Nix flake in this repository.

## Prerequisites

- macOS installed (macOS 14+ recommended)
- Administrator access
- Internet connection
- 1Password account (for SSH keys and secrets)

## Step 1: Install Determinate Nix

Install Nix using the Determinate Nix installer:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Follow the prompts and allow the installer to make system changes.

## Step 2: Configure 1Password

### Install 1Password

Download and install 1Password from the [App Store](https://apps.apple.com/us/app/1password-password-manager/id1333542190) or [website](https://1password.com/downloads/mac/).

### Set Up SSH Key

1. Open 1Password → **Settings** → **Developer**
2. Enable **SSH Agent**
3. Enable **Use the SSH agent**
4. Generate or import an SSH key for GitHub authentication

### Register Key with GitHub

1. Copy your **public key** from 1Password
2. Go to GitHub → **Settings** → **SSH and GPG keys**
3. Click **New SSH key**
4. Add your key for both authentication and signing

## Step 3: Clone the Repository

```bash
git clone git@github.com:funkymonkeymonk/nix.git ~/nix
cd ~/nix
```

## Step 4: Apply Configuration

Run the nix-darwin installer with your target configuration:

```bash
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake github:funkymonkeymonk/nix#<target>
```

Replace `<target>` with your machine configuration:
- `darwin-server` - Headless server with Lume VMs
- `wweaver` - Work laptop

**Note:** The first run takes 10-30 minutes as it downloads packages.

## Step 5: Verify Installation

After the build completes:

1. Open a new terminal to load the new shell configuration
2. Verify tools are available:
   ```bash
   which helix
   which jj
   which devenv
   ```

3. Check that 1Password CLI works:
   ```bash
   op --version
   ```

## Next Steps

- See [Add a New Machine](add-machine.md) if you need to create a custom configuration
- See [Set Up 1Password SSH Signing](setup-1password.md) for commit signing setup

## Troubleshooting

### "Homebrew is not installed"

If you see this error, your target configuration requires Homebrew. Install it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then re-run the nix-darwin command.

### "No SSH keys found"

Ensure:
1. 1Password SSH agent is enabled
2. Your SSH key is in 1Password
3. The key is registered with GitHub

### Build fails with hash mismatch

Clear the Nix cache and retry:

```bash
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake github:funkymonkeymonk/nix#<target> --refresh
```

### Permission denied errors

Make sure you're running the command with `sudo` as shown above.

> **See also:** [nix-darwin documentation](https://daiderd.com/nix-darwin/) for advanced configuration options
