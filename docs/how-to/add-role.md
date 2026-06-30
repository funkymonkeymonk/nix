---
title: "How to Add a New Role"
description: "Create a new role module for grouping packages and configurations"
type: how-to
audience: both
last-reviewed: 2026-06-30
---

# How to Add a New Role

Create a new role module that groups related packages, then enable it on one or more machines.

1. **Create the role module.** Write `modules/roles/\u003cname\u003e.nix` using the standard NixOS module pattern:

    ```nix
    { config, lib, pkgs, ... }: let
      cfg = config.myConfig.roles.new-role;
    in {
      config = lib.mkIf cfg.enable {
        environment.systemPackages = with pkgs; [package1 package2];

        # Optional macOS Homebrew casks (guard with platform check)
        homebrew = lib.mkIf config.myConfig.isDarwin {
          casks = ["some-app"];
        };
      };
    }
    ```

2. **Add the enable option.** In `modules/common/options.nix` under `myConfig.roles`:

    ```nix
    new-role = {
      enable = lib.mkEnableOption "new-role";
    };
    ```

3. **Import the module.** Add to `modules/roles/default.nix`:

    ```nix
    imports = [
      # ... existing roles ...
      ./new-role.nix
    ];
    ```

4. **Enable on a host.** In the target's configuration:

    ```nix
    myConfig.roles.new-role.enable = true;
    ```

5. **Validate:**

    ```bash
    devenv tasks run check:lint
    devenv tasks run test:darwin-eval   # macOS
    devenv tasks run test:nixos-eval    # NixOS
    ```

## Platform-Specific Packages

Guard platform-specific blocks with `lib.mkIf config.myConfig.isDarwin` (macOS only) or `lib.mkIf (!config.myConfig.isDarwin)` (Linux only).

\u003e **See also:** [Roles Reference](../reference/roles.md) for existing role examples
