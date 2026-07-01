---
title: "Set Up Your Mac"
description: "Step-by-step walkthrough for configuring a new macOS machine from this flake"
type: tutorial
audience: both
last-reviewed: 2026-06-30
---

# Set Up Your Mac

This tutorial walks through configuring a macOS machine end-to-end. By the end, you will have Nix applied to your Mac with roles enabled and tools installed.

## Prerequisites

- macOS 14+ (Apple Silicon)
- Nix installed via Determinate Systems ([Getting Started](getting-started.md))
- This repository cloned to `~/nix`
- A 1Password account (for SSH key management)

## Step 1: Install 1Password

1. Install 1Password from the [App Store](https://apps.apple.com/us/app/1password-password-manager/id1333542190)
2. Open 1Password **Settings** → **Developer**
3. Enable **SSH Agent** and **Use the SSH agent**
4. Generate or import an SSH key

Register your public key with GitHub:

1. Copy the public key from 1Password
2. Go to GitHub → **Settings** → **SSH and GPG keys** → **New SSH key**
3. Save it for both authentication and signing

## Step 2: Install the 1Password CLI

```bash
brew install 1password-cli
op signin
```

Follow the browser prompt to authenticate. Once signed in, the CLI caches the session.

## Step 3: Choose Your Roles

Roles bundle packages by purpose. Common picks for a development Mac:

| Role | What You Get |
|------|-------------|
| `developer` | emacs, helix, jj, devenv, docker, kubectl |
| `desktop` | logseq, super-productivity |
| `workstation` | slack, trippy |
| `opencode` | OpenCode AI assistant |
| `pi` | Pi coding agent |

For this tutorial we'll enable `developer`, `desktop`, and `opencode`. You can find the full catalogue in the [Roles Reference](../reference/roles.md).

## Step 4: Create Your Target

Your target directory holds machine-specific settings. Most config comes from roles, so keep it minimal to start:

```bash
mkdir -p targets/my-mac
```

Create `targets/my-mac/default.nix`:

```nix
{
  mkUser,
  ...
}: {
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;
  system.primaryUser = "your-username";

  myConfig =
    mkUser "your-username" "you@example.com"
    // {
      roles = {
        developer.enable = true;
        desktop.enable = true;
        opencode.enable = true;
      };
    };
}
```

Replace `your-username` with your macOS username (run `whoami` to find it). Replace the email address too.

## Step 5: Add Your Target to flake.nix

Open `flake.nix` and add your machine under `darwinConfigurations`. Look for the existing entries (`wweaver`, `MegamanX`) and model yours on them:

```nix
"my-mac" = nix-darwin.lib.darwinSystem {
  specialArgs = { inherit inputs mkUser; };
  modules = [
    configuration
    nix-homebrew.darwinModules.nix-homebrew
    ./modules
    ./modules/roles/homebrew.nix
    ./os/darwin.nix
    ./targets/my-mac
    home-manager.darwinModules.home-manager
    { home-manager.sharedModules = [ opnix.homeManagerModules.default ]; }
  ];
};
```

Notice you need the same module list pattern as the other targets. The key differences per target are the hostname and the target directory path.

## Step 6: Validate Before Building

```bash
devenv tasks run check:lint
devenv tasks run test:darwin-eval
```

Both commands should complete without errors. If lint fails, fix formatting with the suggested commands. If eval fails, check that username and role names are correct.

## Step 7: Build and Apply

```bash
nix build .#darwinConfigurations.my-mac.system
./result/sw/bin/darwin-rebuild switch --flake .#my-mac
```

The first build downloads many packages and can take 10–30 minutes. Subsequent builds are faster because the Nix store caches them.

## Step 8: Verify

Open a new terminal so that environment variables and shell configuration reload, then check:

```bash
jj --version          # developer role
opencode --version    # opencode role
logseq --version      # desktop role (macOS)
devenv tasks list     # devenv is available
```

## What You've Done

- Installed Nix and cloned the flake
- Signed in to 1Password and registered an SSH key
- Created a target directory with role selections
- Added the target to `flake.nix`
- Built and applied the configuration
- Verified tools are installed

## Next Steps

- **[Create Your First Role](create-your-first-role.md)** — Package your own tools together
- **[Add Secrets with opnix](getting-started-opnix.md)** — Manage SSH keys, tokens, and passwords through 1Password
- **Read [Architecture](../explanation/architecture.md)** — Understand how modules, roles, and targets compose
