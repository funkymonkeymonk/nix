# TubeArchivist Host Configuration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make TubeArchivist host configurable with localhost default and drlight hostname override

**Architecture:** Add Nix option for TubeArchivist host configuration, update service module to use configurable host, set drlight-specific configuration

**Tech Stack:** NixOS modules, Docker containers, environment variables

### Task 1: Add TubeArchivist Host Option to Common Options

**Files:**
- Modify: `modules/common/options.nix`

**Step 1: Add the new option definition**

Find the `myConfig` options block and add TubeArchivist configuration:

```nix
tubearchivist = {
  host = lib.mkOption {
    type = lib.types.str;
    default = "localhost";
    description = "Hostname for TubeArchivist service";
  };
};
```

**Step 2: Run nix flake check to validate syntax**

Run: `nix flake check`
Expected: No syntax errors, option validation passes

**Step 3: Commit**

```bash
git add modules/common/options.nix
git commit -m "feat: add configurable TubeArchivist host option"
```

### Task 2: Update Service Module to Use Configurable Host

**Files:**
- Modify: `modules/nixos/services.nix:54-55`

**Step 1: Write the failing test (manual validation)**

Current hardcoded values will remain unchanged, so we'll verify the module still builds:

Run: `nix build .#nixosConfigurations.drlight.config.system.build.toplevel --dry-run`
Expected: PASS (current hardcoded configuration still works)

**Step 2: Replace hardcoded TA_HOST with configurable option**

Replace line 54:
```nix
TA_HOST = "http://192.168.1.23:8000";
```

With:
```nix
TA_HOST = "http://${config.myConfig.tubearchivist.host}:8000";
```

**Step 3: Update ALLOWED_HOSTS to use configurable host**

Replace line 55:
```nix
ALLOWED_HOSTS = "localhost,127.0.0.1,192.168.1.23";
```

With:
```nix
ALLOWED_HOSTS = if config.myConfig.tubearchivist.host == "localhost"
  then "localhost,127.0.0.1"
  else "localhost,127.0.0.1,${config.myConfig.tubearchivist.host}";
```

**Step 4: Test build still works with default**

Run: `nix build .#nixosConfigurations.drlight.config.system.build.toplevel --dry-run`
Expected: PASS (uses default localhost)

**Step 5: Commit**

```bash
git add modules/nixos/services.nix
git commit -m "feat: use configurable TubeArchivist host in service module"
```

### Task 3: Configure drlight with Custom Hostname

**Files:**
- Modify: `targets/drlight/default.nix`

**Step 1: Add TubeArchivist configuration to drlight**

Add to the myConfig section:
```nix
tubearchivist = {
  host = "drlight";
};
```

**Step 2: Test drlight configuration builds**

Run: `nix build .#nixosConfigurations.drlight.config.system.build.toplevel --dry-run`
Expected: PASS with hostname set to "drlight"

**Step 3: Test other systems still work with default**

Run: `nix build .#nixosConfigurations.zero.config.system.build.toplevel --dry-run`
Expected: PASS with default localhost host

**Step 4: Verify environment variables are set correctly**

Run: `nix eval .#nixosConfigurations.drlight.config.systemd.services.docker-tubearchivist.environment --json`
Expected: Contains `"TA_HOST": "http://drlight:8000"` and `"ALLOWED_HOSTS": "localhost,127.0.0.1,drlight"`

**Step 5: Commit**

```bash
git add targets/drlight/default.nix
git commit -m "feat: configure drlight TubeArchivist host"
```

### Task 4: Comprehensive Validation

**Files:**
- Test: `nix flake check`

**Step 1: Run comprehensive validation**

Run: `task test:full`
Expected: All configurations pass validation

**Step 2: Verify drlight environment**

Run: `nix eval .#nixosConfigurations.drlight.config.virtualisation.oci-containers.containers.tubearchivist.environment --json`
Expected:
```json
{
  "TA_HOST": "http://drlight:8000",
  "ALLOWED_HOSTS": "localhost,127.0.0.1,drlight"
}
```

**Step 3: Verify zero system uses defaults**

Run: `nix eval .#nixosConfigurations.zero.config.virtualisation.oci-containers.containers.tubearchivist.environment --json`
Expected:
```json
{
  "TA_HOST": "http://localhost:8000", 
  "ALLOWED_HOSTS": "localhost,127.0.0.1"
}
```

**Step 4: Final commit**

```bash
git add .
git commit -m "feat: complete TubeArchivist host configuration"
```

## Final Verification Commands

After all tasks:
```bash
# Validate all configurations
task test:full

# Check drlight specifically
nix eval .#nixosConfigurations.drlight.config.virtualisation.oci-containers.containers.tubearchivist.environment --json

# Check zero uses defaults  
nix eval .#nixosConfigurations.zero.config.virtualisation.oci-containers.containers.tubearchivist.environment --json
```