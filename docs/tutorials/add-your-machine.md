# Add Your Machine to the Flake

In this tutorial, you'll create a personalized machine configuration with your own choice of roles. By the end, you'll have a working Darwin or NixOS target that applies your preferred toolset.

## What You'll Learn

- How targets, roles, and the flake fit together
- How to create a target directory for your machine
- How to wire it into `flake.nix` with `mkUser` and roles
- How to build and apply the configuration

## Prerequisites

- Completed the [Getting Started](getting-started.md) tutorial
- A machine with Nix installed and this repo cloned
- About 20 minutes

## Step 1: Choose Your Roles

Roles bundle packages and configuration by use case. Pick the ones that match what you do:

| Role | What You Get |
|------|-------------|
| `developer` | Dev tools (python, node, k9s, yaks), jj, zellij |
| `creative` | Media tools (ffmpeg, imagemagick, pandoc) |
| `desktop` | Desktop apps (logseq, super-productivity) |
| `workstation` | Work tools (slack, trippy) |
| `opencode` | OpenCode AI assistant + rtk |
| `claude` | Claude Code AI assistant + rtk |
| `entertainment` | Steam, OBS, Discord (macOS only) |
| `gaming` | Moonlight game streaming |

For this tutorial, we'll use `developer` and `desktop`. You can adjust later.

> For the full list, see [Roles Reference](../reference/roles.md).

## Step 2: Create Your Target Directory

Pick a name for your machine. We'll use `my-laptop` as an example:

```bash
mkdir -p targets/my-laptop
```

## Step 3: Create the Target Configuration

Create `targets/my-laptop/default.nix`. For most machines, this can be minimal -- roles handle the heavy lifting:

```nix
# targets/my-laptop/default.nix
_: {
  # Machine-specific overrides go here.
  # Most config comes from roles selected in flake.nix.
}
```

If you're on NixOS and need hardware-specific config, generate it first:

```bash
nixos-generate-config --show-hardware-config > targets/my-laptop/hardware-configuration.nix
```

Then import it:

```nix
# targets/my-laptop/default.nix (NixOS with hardware config)
{...}: {
  imports = [./hardware-configuration.nix];
  networking.hostName = "my-laptop";
}
```

## Step 4: Add Your Machine to flake.nix

Open `flake.nix` and find the `darwinConfigurations` section (for macOS) or `nixosConfigurations` (for NixOS).

### macOS

Add your machine alongside the existing entries:

```nix
"my-laptop" = mkDarwinHost {
  target = ./targets/my-laptop;
  user = mkUser "yourusername" "you@example.com";
  roles = ["developer" "desktop" "opencode"];
};
```

### NixOS

```nix
"my-laptop" = mkNixosHost {
  target = ./targets/my-laptop;
  user = mkUser "yourusername" "you@example.com";
  roles = ["developer" "desktop"];
};
```

The `mkUser` helper sets up your user account with common defaults (admin, 1Password, development tools). The `roles` list determines which packages and skills get installed.

## Step 5: Validate the Configuration

Before building, check that everything evaluates correctly:

```bash
# Lint check (fast, catches syntax issues)
devenv tasks run check:lint

# Platform-specific eval test
devenv tasks run test:darwin-eval    # macOS
devenv tasks run test:nixos-eval     # NixOS
```

Both should pass. If you get errors, check that:
- Your target path matches the directory you created
- The username in `mkUser` matches your system username
- Roles are spelled correctly (check `modules/common/options.nix`)

## Step 6: Build and Apply

### macOS

```bash
nix build .#darwinConfigurations.my-laptop.system
./result/sw/bin/darwin-rebuild switch --flake .#my-laptop
```

### NixOS

```bash
sudo nixos-rebuild switch --flake .#my-laptop
```

This may take several minutes the first time as packages download.

## Step 7: Verify

Open a new terminal and check that your tools are available:

```bash
# If you enabled the developer role
jj --version
yx --version
k9s version

# If you enabled opencode
opencode --version
```

## What You've Learned

- **Targets** hold machine-specific config (mostly empty for simple setups)
- **Roles** bundle packages and config by use case
- `mkUser` creates your user with sensible defaults
- `flake.nix` composes targets + roles into a full system configuration
- Always validate with lint + eval before applying

## What's Next

- **Create a custom role**: See [Create Your First Role](create-your-first-role.md) to package your own tools
- **Add an AI skill**: See [Write Your First Skill](write-your-first-skill.md)
- **Understand the architecture**: Read [Architecture](../explanation/architecture.md)
- **Explore all options**: See [Options Reference](../reference/options.md)
