---
title: "Add a New Role"
description: "How to create a new role module for grouping packages and configurations"
type: how-to
audience: both
automation-ready: false
last-reviewed: 2026-04-06
---

# Add a New Role

This guide shows you how to create a new role for grouping packages and configurations.

## Step 1: Create the Role Module

Create a new file `modules/roles/<name>.nix` using the standard NixOS module pattern:

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.my-role;
in {
  config = lib.mkIf cfg.enable {
    # Packages available on all platforms
    environment.systemPackages = with pkgs; [
      package1
      package2
    ];

    # Optional: Role-specific configuration
    environment.variables = {
      MY_VAR = "value";
    };

    # Optional: macOS Homebrew casks (guard with platform check)
    homebrew = lib.mkIf config.myConfig.isDarwin {
      casks = [
        "some-app"
      ];
    };
  };
}
```

## Step 2: Add the Enable Option

Add your role's enable option to `modules/common/options.nix` under `myConfig.roles`:

```nix
myConfig.roles.my-role.enable = lib.mkEnableOption "my-role";
```

## Step 3: Import the Module

Add your new module to `modules/roles/default.nix`:

```nix
{
  imports = [
    # ... existing roles ...
    ./my-role.nix
  ];
}
```

## Step 4: Enable the Role

Enable your role in a host configuration:

```nix
myConfig.roles.my-role.enable = true;
```

## Step 5: Document the Role

Add your role to `docs/reference/roles.md`:

```markdown
### my-role

Brief description of the role's purpose.

**Packages:** package1, package2

**Homebrew Casks (macOS):** some-app
```

## Platform-Specific Packages

To include packages only on certain platforms, use conditional logic in the module:

```nix
config = lib.mkIf cfg.enable {
  # All platforms
  environment.systemPackages = with pkgs; [common-tool];

  # macOS only
  homebrew = lib.mkIf config.myConfig.isDarwin {
    casks = ["macos-app"];
  };

  # Linux only
  environment.systemPackages = lib.mkIf (!config.myConfig.isDarwin) (with pkgs; [
    linux-only-tool
  ]);
};
```

## Validation

After adding your role:

```bash
# Check syntax and formatting
devenv tasks run check:lint

# Test that configurations evaluate correctly
devenv tasks run test:darwin-eval
devenv tasks run test:nixos-eval
```

> **See also:** [Roles Reference](../reference/roles.md) for existing role examples
