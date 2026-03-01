# Getting Started

This tutorial walks you through setting up this Nix configuration on a new machine. By the end, you'll have a fully configured development environment.

## What You'll Learn

- How to install Nix with flakes
- How to apply this configuration to your machine
- How to verify everything works

## Prerequisites

- A macOS (Apple Silicon) or Linux (x86_64) machine
- Terminal access
- About 30 minutes

## Step 1: Install Nix

If you don't have Nix installed, use the Determinate Systems installer:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Restart your terminal after installation.

Verify Nix is working:

```bash
nix --version
```

You should see output like `nix (Nix) 2.x.x`.

## Step 2: Clone This Repository

```bash
git clone https://github.com/funkymonkeymonk/nix.git
cd nix
```

## Step 3: Enter the Development Environment

```bash
nix develop
```

This may take a few minutes the first time as it downloads dependencies. When complete, you'll be in a shell with all development tools available.

## Step 4: Review Available Configurations

List the available system configurations:

```bash
# For macOS
nix flake show | grep darwinConfigurations

# For NixOS
nix flake show | grep nixosConfigurations
```

You'll see configurations like `wweaver`, `MegamanX`, `drlight`, and `zero`.

## Step 5: Create Your Configuration

For a new machine, you'll need to create a target. For now, let's test with the `core` configuration which provides minimal tooling.

### On macOS

```bash
# Build and apply the core configuration
nix build .#darwinConfigurations.core.system
./result/sw/bin/darwin-rebuild switch --flake .#core
```

### On NixOS

NixOS requires hardware-specific configuration. See the [Add a New Machine](../how-to/add-machine.md) guide for detailed steps.

## Step 6: Verify Installation

After applying the configuration:

```bash
# Check that devenv is available
devenv --version

# List available tasks
devenv tasks list
```

You should see a list of available tasks like `ci:quick`, `test:full`, etc.

## Step 7: Run Validation

Verify your configuration is healthy:

```bash
devenv tasks run ci:quick
```

This runs fast lint and format checks (~30 seconds).

## What's Next?

Now that you have the basics working:

- **Customize your setup**: See [Add a New Machine](../how-to/add-machine.md) to create a personalized configuration
- **Understand the architecture**: Read [Architecture](../explanation/architecture.md) to learn how modules, bundles, and roles work
- **Explore available roles**: Check [Roles Reference](../reference/roles.md) for available package bundles

## Troubleshooting

### "experimental-features" error

Add this to `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

### Build takes too long

First builds download many packages. Subsequent builds use the cache and are much faster.

### Permission denied errors

On macOS, you may need to run:

```bash
sudo chown -R $(whoami) /nix
```

> For more troubleshooting help, see the reference documentation or check existing issues in the repository.
