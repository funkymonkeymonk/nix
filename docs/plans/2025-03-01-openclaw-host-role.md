# OpenClaw Host Role Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deconstruct the standalone openclaw-local flake into the nix repo as a new "openclaw-host" role, integrating the nix-openclaw home-manager module.

**Architecture:** The openclaw-local flake is a standalone home-manager configuration that uses nix-openclaw. We'll integrate it into the main nix repo by: 1) Adding nix-openclaw as a flake input, 2) Creating an "openclaw-host" role in bundles.nix that enables the home-manager module, 3) Updating flake.nix to include the nix-openclaw overlay and home-manager module.

**Tech Stack:** Nix, nix-openclaw (GitHub:openclaw/nix-openclaw), home-manager

---

## Prerequisites

Read these files before starting:
- `/home/monkey/repos/openclaw-local/flake.nix` - Source flake to deconstruct
- `/home/monkey/repos/nix/flake.nix` - Target flake to modify
- `/home/monkey/repos/nix/bundles.nix` - Role definitions
- `/home/monkey/repos/nix/modules/common/options.nix` - Options definitions

---

### Task 1: Add nix-openclaw Flake Input

**Files:**
- Modify: `/home/monkey/repos/nix/flake.nix:1-47` (inputs section)

**Step 1: Add the nix-openclaw input**

Add after the `devenv` input:

```nix
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    nix-openclaw.inputs.nixpkgs.follows = "nixpkgs";
```

**Step 2: Add to outputs function parameters**

Add `nix-openclaw` to the outputs function parameters after `devenv`:

```nix
  outputs = {
    self,
    nix-darwin,
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    mac-app-util,
    nix-homebrew,
    homebrew-core,
    homebrew-cask,
    opnix,
    microvm,
    nix-openclaw,  # ADD THIS
    ...
  } @ inputs: let
```

**Step 3: Commit**

```bash
cd /home/monkey/repos/nix
git add flake.nix
git commit -m "feat: add nix-openclaw flake input"
```

---

### Task 2: Add nix-openclaw Overlay

**Files:**
- Modify: `/home/monkey/repos/nix/flake.nix:62-73` (overlays section in configuration)

**Step 1: Add the nix-openclaw overlay**

Add after the devenv overlay:

```nix
          # nix-openclaw overlay
          (final: _prev: {
            inherit (nix-openclaw.packages.${final.system}) openclaw;
          })
          nix-openclaw.overlays.default
```

**Step 2: Commit**

```bash
cd /home/monkey/repos/nix
git add flake.nix
git commit -m "feat: add nix-openclaw overlay"
```

---

### Task 3: Add home-manager Module Integration

**Files:**
- Modify: `/home/monkey/repos/nix/flake.nix:239-242` and similar home-manager sections

**Step 1: Add nix-openclaw home-manager module to Darwin configs**

Find the `home-manager.darwinModules.home-manager` section (around line 239) and update:

```nix
            home-manager.darwinModules.home-manager
            {
              home-manager.sharedModules = [
                opnix.homeManagerModules.default
                nix-openclaw.homeManagerModules.openclaw  # ADD THIS
              ];
            }
```

**Step 2: Add to NixOS configs**

Find the NixOS home-manager section (around line 276) and similarly update:

```nix
            home-manager.nixosModules.home-manager
            {
              home-manager.sharedModules = [
                opnix.homeManagerModules.default
                nix-openclaw.homeManagerModules.openclaw  # ADD THIS
              ];
            }
```

**Step 3: Commit**

```bash
cd /home/monkey/repos/nix
git add flake.nix
git commit -m "feat: add nix-openclaw home-manager module"
```

---

### Task 4: Create openclaw-host Role

**Files:**
- Modify: `/home/monkey/repos/nix/bundles.nix:210-223` (after llm-host role)

**Step 1: Add openclaw-host role**

Add after the `llm-server` role definition:

```nix
    openclaw-host = {
      packages = with pkgs; [
        openclaw
      ];

      enableAgentSkills = true;

      config = {};
    };
```

**Step 2: Commit**

```bash
cd /home/monkey/repos/nix
git add bundles.nix
git commit -m "feat: add openclaw-host role to bundles"
```

---

### Task 5: Create OpenClaw Options Module

**Files:**
- Create: `/home/monkey/repos/nix/modules/home-manager/openclaw.nix`

**Step 1: Create the openclaw configuration module**

This module will configure the `programs.openclaw` home-manager option provided by nix-openclaw.

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.openclaw-host;
in {
  options.myConfig.openclaw-host = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable OpenClaw host configuration";
    };

    documents = mkOption {
      type = types.path;
      default = ./documents;
      description = "Path to OpenClaw documents directory";
    };

    configPath = mkOption {
      type = types.str;
      default = "";
      description = "Path to OpenClaw config file";
    };
  };

  config = mkIf cfg.enable {
    programs.openclaw = {
      documents = cfg.documents;

      instances.default = {
        enable = true;
        configPath = mkIf (cfg.configPath != "") cfg.configPath;
        config = {
          plugins = {
            allow = [ "matrix" ];
          };
          gateway = {
            mode = "local";
          };
        };
      };
    };

    # Activation script for matrix plugin
    home.activation.installMatrixPlugin = lib.hm.dag.entryAfter [ "installPackages" ] ''
      cd ~/.openclaw/extensions/matrix
      if [ -f package.json ]; then
        PATH="$HOME/.nix-profile/bin:$PATH" npm install --ignore-scripts 2>/dev/null || true
        PATH="$HOME/.nix-profile/bin:$PATH" node node_modules/@matrix-org/matrix-sdk-crypto-nodejs/download-lib.js 2>/dev/null || true
      fi
    '';
  };
}
```

**Step 2: Import the module in flake.nix**

Add to the `commonModules` list in `/home/monkey/repos/nix/flake.nix`:

```nix
    # Common module imports
    commonModules = [
      ./modules/common/options.nix
      ./modules/common/users.nix
      ./modules/common/shell.nix
      ./modules/common/onepassword.nix
      ./modules/common/cachix.nix
      ./modules/home-manager/openclaw.nix  # ADD THIS
    ];
```

**Step 3: Commit**

```bash
cd /home/monkey/repos/nix
git add modules/home-manager/openclaw.nix flake.nix
git commit -m "feat: add openclaw-host configuration module"
```

---

### Task 6: Update Role to Enable Configuration

**Files:**
- Modify: `/home/monkey/repos/nix/bundles.nix:266-270` (openclaw-host role)

**Step 1: Update openclaw-host to enable the configuration**

Update the role to include the configuration option:

```nix
    openclaw-host = {
      packages = with pkgs; [
        openclaw
      ];

      enableAgentSkills = true;

      config = {
        myConfig.openclaw-host.enable = true;
      };
    };
```

**Step 2: Commit**

```bash
cd /home/monkey/repos/nix
git add bundles.nix
git commit -m "feat: enable openclaw-host configuration in role"
```

---

### Task 7: Test the Configuration

**Files:**
- Run: Validation commands

**Step 1: Run quality checks**

```bash
cd /home/monkey/repos/nix
direnv allow  # if needed
direnv reload  # if needed
deval tasks run quality:check
```

Expected: Formatting and linting pass

**Step 2: Validate flake builds**

```bash
cd /home/monkey/repos/nix
nix flake check --no-build 2>&1 | head -50
```

Expected: No errors

**Step 3: Test a specific host with the new role**

Pick a host (e.g., `drlight` or `MegamanX`) and test with the new role:

```bash
# Dry run build to catch errors early
nix build .#darwinConfigurations.MegamanX.config.system.build.toplevel --dry-run 2>&1 | head -30
```

Or for NixOS:

```bash
nix build .#nixosConfigurations.drlight.config.system.build.toplevel --dry-run 2>&1 | head -30
```

Expected: No evaluation errors

**Step 4: Commit**

```bash
cd /home/monkey/repos/nix
git status  # verify all changes are committed
git log --oneline -5  # show recent commits
```

---

### Task 8: Archive Original Flake (Optional)

**Files:**
- Create: `/home/monkey/repos/openclaw-local/README.md`

**Step 1: Document the migration**

Create a README explaining the migration:

```markdown
# OpenClaw Local - Migrated

This standalone flake has been deconstructed and integrated into the main nix repo.

The OpenClaw configuration is now available as the `openclaw-host` role in:
- `/home/monkey/repos/nix/bundles.nix` - Role definition
- `/home/monkey/repos/nix/modules/home-manager/openclaw.nix` - Configuration module

To use the openclaw-host role, add it to your host's roles list in flake.nix.
```

**Step 2: Commit (in openclaw-local repo)**

```bash
cd /home/monkey/repos/openclaw-local
git add README.md
git commit -m "docs: document migration to nix repo"
```

---

## Summary

After completing all tasks:

1. nix-openclaw is available as a flake input
2. The nix-openclaw overlay provides the `openclaw` package
3. The home-manager module is imported for all hosts
4. The `openclaw-host` role is available in bundles.nix
5. Using the role automatically enables OpenClaw configuration
6. Quality checks pass
7. Original flake is documented as migrated

**Verification:**
- Run `devenv tasks run quality:check` - should pass
- Run `nix flake check --no-build` - should show no errors
- Add `openclaw-host` role to a host and verify it builds
