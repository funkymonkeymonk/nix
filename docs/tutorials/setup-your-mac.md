---
title: "Set Up Your Mac"
description: "Step-by-step walkthrough for configuring a new macOS machine from this flake"
type: tutorial
audience: both
last-reviewed: 2026-11-10
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

## Step 3: Choose a machine profile and roles

The wizard offers compatible archetypes and additional roles separately. An archetype is the base configuration bundle; roles add optional capabilities. Review the [Roles Reference](../reference/roles.md) to choose roles that fit your Mac. Common options include `developer`, `desktop`, `workstation`, `opencode`, and `pi`.

## Step 4: Create and register the Mac target

From the repository's devenv environment, run:

```bash
devenv tasks run machines:new
```

Choose **Darwin** and `aarch64-darwin`, then answer the identity, SecretSpec profile, archetype, and role prompts. Confirm the summary to generate the machine module and catalog entry. The wizard can optionally evaluate the new target, but it does not build or apply the configuration.

See [Create a Machine Target](../how-to/create-machine-target.md) for supported systems, generated paths, prompt details, and the NixOS follow-up requirements. If you need a target that cannot be expressed by the wizard's choices, an advanced manual configuration can follow the existing machine modules and catalog records.

## Step 5: Validate the configuration

Review the generated files, then run:

```bash
devenv tasks run check:lint
devenv tasks run test:eval
```

Both commands should complete without errors. If evaluation fails, check the user and role names, and ensure the generated files are visible to Nix's flake source.

## Step 6: Build and apply

Once validation succeeds, build the Darwin configuration and apply it:

```bash
nix build .#darwinConfigurations.my-mac.system
./result/sw/bin/darwin-rebuild switch --flake .#my-mac
```

Replace `my-mac` with the machine output name chosen in the wizard. The first build downloads many packages and can take 10–30 minutes. Subsequent builds are faster because the Nix store caches them.

## Step 7: Verify

Open a new terminal so that environment variables and shell configuration reload, then check:

```bash
jj --version          # developer role
opencode --version    # opencode role
logseq --version      # desktop role (macOS)
devenv tasks list      # devenv is available
```

## What You've Done

- Installed Nix and signed in to 1Password
- Created a machine module and registered its target with the wizard
- Validated, built, and applied the configuration
- Verified tools are installed

## Next Steps

- **[Create Your First Role](create-your-first-role.md)** — Package your own tools together
- **[Add Secrets with opnix](getting-started-opnix.md)** — Manage SSH keys, tokens, and passwords through 1Password
- **Read [Architecture](../explanation/architecture.md)** — Understand how modules, roles, and targets compose
