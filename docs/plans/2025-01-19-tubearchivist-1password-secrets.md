# TubeArchivist 1Password Secrets Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace hardcoded TubeArchivist credentials with opnix-based 1Password secrets management

**Architecture:** Add opnix flake input, create secrets module for credential retrieval, update services to use dynamic credentials

**Tech Stack:** opnix, 1Password CLI, NixOS modules, Docker containers

### Task 1: Add opnix Input to Flake

**Files:**
- Modify: `flake.nix:4-34`

**Step 1: Add opnix input to flake inputs**

Add after line 21:
```nix
opnix.url = "github:brizzbuzz/opnix";
```

**Step 2: Run nix flake check to validate input**

Run: `nix flake check`
Expected: No input errors, opnix properly resolved

**Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat: add opnix flake input for 1Password secrets"
```

### Task 2: Create opnix Secrets Module

**Files:**
- Create: `modules/common/opnix-secrets.nix`

**Step 1: Write the basic opnix secrets module**

```nix
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.myConfig.tubearchivist;
in {
  options.myConfig.tubearchivist.secrets = {
    username = lib.mkOption {
      type = lib.types.str;
      description = "TubeArchivist username from 1Password";
    };
    
    password = lib.mkOption {
      type = lib.types.str;
      description = "TubeArchivist password from 1Password";
    };
  };

  config = lib.mkIf (cfg.secrets.username != "" && cfg.secrets.password != "") {
    # opnix will handle the secret retrieval
    # This module provides the interface for services to use
  };
}
```

**Step 2: Run nix flake check to validate module**

Run: `nix flake check`
Expected: Module syntax valid, options properly defined

**Step 3: Commit**

```bash
git add modules/common/opnix-secrets.nix
git commit -m "feat: create opnix secrets module for TubeArchivist"
```

### Task 3: Integrate opnix Module into Configuration

**Files:**
- Modify: `flake.nix:60-64` (drlight configuration)
- Modify: `flake.nix:87-91` (zero configuration)

**Step 1: Add opnix-secrets module to drlight configuration**

Find the modules list in drlight config, add after `./modules/common/users.nix`:
```nix
./modules/common/opnix-secrets.nix
```

**Step 2: Add opnix-secrets module to zero configuration**

Find the modules list in zero config, add after `./modules/common/users.nix`:
```nix
./modules/common/opnix-secrets.nix
```

**Step 3: Test configuration builds**

Run: `nix build .#nixosConfigurations.drlight.config.system.build.toplevel --dry-run`
Expected: PASS with opnix-secrets module included

**Step 4: Commit**

```bash
git add flake.nix
git commit -m "feat: integrate opnix secrets module into NixOS configurations"
```

### Task 4: Update Service Module to Use opnix Secrets

**Files:**
- Modify: `modules/nixos/services.nix:56-61`

**Step 1: Write the failing test (manual validation)**

Current hardcoded credentials should still work:

Run: `nix eval .#nixosConfigurations.drlight.config.virtualisation.oci-containers.containers.tubearchivist.environment --json`
Expected: Shows hardcoded "tubearchivist" for both username and password

**Step 2: Replace hardcoded credentials with opnix secrets**

Replace lines 56-57:
```nix
TA_USERNAME = "tubearchivist";
TA_PASSWORD = "tubearchivist";
```

With:
```nix
TA_USERNAME = config.myConfig.tubearchivist.secrets.username;
TA_PASSWORD = config.myConfig.tubearchivist.secrets.password;
```

**Step 3: Update drlight configuration to provide opnix secrets**

Add to drlight myConfig section:
```nix
tubearchivist = {
  host = "drlight";
  secrets = {
    username = builtins.readFile (pkgs.opnix {
      item = "TubeArchivist";
      field = "username";
    });
    password = builtins.readFile (pkgs.opnix {
      item = "TubeArchivist";
      field = "password";
    });
  };
};
```

**Step 4: Test build with opnix secrets**

Run: `nix build .#nixosConfigurations.drlight.config.system.build.toplevel --dry-run`
Expected: FAIL initially because 1Password item doesn't exist yet

**Step 5: Create 1Password item for testing**

Run: 
```bash
op item create "TubeArchivist" --username tubearchivist --password tubearchivist
```

**Step 6: Test build again**

Run: `nix build .#nixosConfigurations.drlight.config.system.build.toplevel --dry-run`
Expected: PASS with 1Password secrets retrieved

**Step 7: Commit**

```bash
git add modules/nixos/services.nix targets/drlight/default.nix
git commit -m "feat: replace hardcoded TubeArchivist credentials with opnix secrets"
```

### Task 5: Update Zero Configuration for Shared Credentials

**Files:**
- Modify: `targets/zero/default.nix:67-81`

**Step 1: Add same opnix secrets configuration to zero**

Add to zero myConfig section:
```nix
tubearchivist = {
  host = "localhost"; # Use default
  secrets = {
    username = builtins.readFile (pkgs.opnix {
      item = "TubeArchivist";
      field = "username";
    });
    password = builtins.readFile (pkgs.opnix {
      item = "TubeArchivist";
      field = "password";
    });
  };
};
```

**Step 2: Test zero configuration**

Run: `nix build .#nixosConfigurations.zero.config.system.build.toplevel --dry-run`
Expected: PASS with shared 1Password credentials

**Step 3: Verify environment variables contain opnix values**

Run: `nix eval .#nixosConfigurations.zero.config.virtualisation.oci-containers.containers.tubearchivist.environment --json`
Expected: Shows username/password from 1Password (same as drlight)

**Step 4: Commit**

```bash
git add targets/zero/default.nix
git commit -m "feat: configure zero system to use shared 1Password TubeArchivist credentials"
```

### Task 6: Comprehensive Validation and Cleanup

**Files:**
- Test: `nix flake check` and environment variable verification

**Step 1: Run comprehensive validation**

Run: `task test:full`
Expected: All configurations pass validation with opnix integration

**Step 2: Verify drlight uses 1Password secrets**

Run: `nix eval .#nixosConfigurations.drlight.config.virtualisation.oci-containers.containers.tubearchivist.environment --json`
Expected: Contains username/password from 1Password item "TubeArchivist"

**Step 3: Verify zero uses same 1Password secrets**

Run: `nix eval .#nixosConfigurations.zero.config.virtualisation.oci-containers.containers.tubearchivist.environment --json`
Expected: Contains same username/password as drlight from shared 1Password item

**Step 4: Clean up hardcoded credentials from services.nix**

Verify no hardcoded "tubearchivist" credentials remain in the service module

**Step 5: Final commit**

```bash
git add .
git commit -m "feat: complete opnix integration for TubeArchivist credential management"
```

## Final Verification Commands

After all tasks:
```bash
# Validate all configurations with opnix integration
task test:full

# Verify both systems use same 1Password credentials
nix eval .#nixosConfigurations.drlight.config.virtualisation.oci-containers.containers.tubearchivist.environment --json
nix eval .#nixosConfigurations.zero.config.virtualisation.oci-containers.containers.tubearchivist.environment --json

# Verify 1Password item exists and has expected fields
op item get "TubeArchivist"
```