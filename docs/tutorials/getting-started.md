# Getting Started with Nix System Configuration

In this tutorial, you'll set up a new machine with this Nix configuration system. By the end, you'll have a working development environment with all your tools configured automatically.

## What You'll Learn

- How to bootstrap a new machine with Nix
- How the configuration system works
- How to apply and update your configuration

## Prerequisites

- A macOS or Linux machine
- Internet connection
- About 30 minutes

## Step 1: Bootstrap Your Machine

Run the bootstrap script to install Nix and apply the base configuration:

```bash
curl -fsSL https://raw.githubusercontent.com/funkymonkeymonk/nix/main/bootstrap.sh | bash
```

This script:
1. Installs Nix using the Determinate Systems installer
2. Clones this repository to `~/repos/nix`
3. Applies the `core` configuration with essential tools

Wait for the script to complete. You'll see output showing each step.

## Step 2: Enter the Development Environment

Navigate to the repository and enter the development shell:

```bash
cd ~/repos/nix
devenv shell
```

You should see a message indicating the environment is ready. The shell now has all the tools needed to work with this configuration.

## Step 3: Test the Configuration

Verify everything is working:

```bash
devenv tasks run test
```

This runs quick validation checks on the configuration. You should see all checks pass.

## Step 4: Explore Available Tasks

See what commands are available:

```bash
devenv tasks list
```

You'll see tasks like:
- `switch` - Apply configuration changes
- `test` - Run validation
- `fmt` - Format Nix files
- `build` - Build configurations (dry-run)

## Step 5: Make Your First Change

Let's customize your configuration. Open `flake.nix` and find your machine's configuration. You can add or remove roles to customize what gets installed.

For example, to add the `creative` role (media tools), you would modify the roles list in your target configuration.

## Step 6: Apply Your Changes

Apply your configuration changes:

```bash
devenv tasks run switch
```

This rebuilds and activates your configuration. After it completes, your changes are live.

## What's Next?

Now that you have a working setup:

- **Add a new machine**: See [How to Add a New Machine](../how-to/add-new-machine.md)
- **Configure agent skills**: See [How to Add Custom Skills](../how-to/add-custom-skill.md)
- **Understand the architecture**: See [Architecture Overview](../explanation/architecture.md)

> For a complete list of available roles and what they include, see the [Roles Reference](../reference/roles.md).
