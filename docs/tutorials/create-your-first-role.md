---
title: "Create Your First Role"
description: "Learn how to create a reusable role module for grouping packages"
type: tutorial
audience: both
last-reviewed: 2026-06-30
---

# Create Your First Role

In this tutorial you will bundle related tools into a single toggleable role. By the end, any machine in the flake can enable your role with one option.

## Prerequisites

- Completed [Getting Started](getting-started.md) and either the Mac or NixOS setup tutorial
- Familiarity with `modules/` and `targets/` directories from earlier tutorials
- About 20 minutes

## Step 1: Plan the Role

Pick a name and a set of packages. We'll create a `writing` role for prose work:

| Tool | Purpose |
|------|---------|
| vale | Prose linter |
| pandoc | Document converter |
| mdbook | Book builder from Markdown |

## Step 2: Define the Enable Option

Open `modules/common/options.nix` and find the `myConfig.roles` section alongside existing role definitions. Add:

```nix
writing = {
  enable = lib.mkEnableOption "writing tools (vale, pandoc, mdbook)";
};
```

This creates a boolean option at `myConfig.roles.writing.enable` that defaults to `false`.

## Step 3: Create the Role Module

Create `modules/roles/writing.nix`:

```nix
{ config, lib, pkgs, ... }: let
  cfg = config.myConfig.roles.writing;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      vale
      pandoc
      mdbook
    ];
  };
}
```

The pattern `lib.mkIf cfg.enable` ensures the packages install only when the role is activated. Notice we do not hard-code any platform assumptions here — `vale`, `pandoc`, and `mdbook` are available on both Darwin and Linux.

## Step 4: Import the Module

Add the module to `modules/roles/default.nix`:

```nix
imports = [
  # ... other roles ...
  ./writing.nix
];
```

## Step 5: Validate

Before applying, verify the flake still evaluates cleanly:

```bash
devenv tasks run check:lint
devenv tasks run test:darwin-eval    # macOS
devenv tasks run test:nixos-eval     # NixOS
```

Both should pass. If you see "option myConfig.roles.writing does not exist", double-check Step 2 for a typo.

## Step 6: Enable the Role on Your Machine

In your target configuration under `targets/`, enable the role inside `myConfig`:

```nix
roles = {
  developer.enable = true;
  writing.enable = true;    # add this line
};
```

Then rebuild:

```bash
# macOS
./result/sw/bin/darwin-rebuild switch --flake .#your-target

# NixOS
sudo nixos-rebuild switch --flake .#your-target
```

## Step 7: Verify the Installation

Open a new terminal and confirm the tools are present:

```bash
vale --version
pandoc --version
mdbook --version
```

You will see version info from each tool. If one is missing, check that `myConfig.roles.writing.enable = true` was actually written to your target before rebuilding.

## Optional: Platform-Specific Packages

To add macOS-only Homebrew casks to the same role, guard with a platform check:

```nix
config = lib.mkIf cfg.enable {
  environment.systemPackages = with pkgs; [vale pandoc mdbook];

  homebrew = lib.mkIf config.myConfig.isDarwin {
    casks = ["marked"];  # Markdown previewer (macOS only)
  };
};
```

## What You Learned

- Roles are NixOS modules gated by `lib.mkIf cfg.enable`
- Options live in `modules/common/options.nix` under `myConfig.roles`
- Modules go in `modules/roles/<name>.nix` and import via `default.nix`
- Platform-specific code uses `lib.mkIf config.myConfig.isDarwin`

## See Also

For a quick checklist when adding any role (not this first one), see [Add a New Role](../how-to/add-role.md).
