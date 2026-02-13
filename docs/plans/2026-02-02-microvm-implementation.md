# Microvm Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add microvm.nix support to create a `dev-vm` that reuses existing roles and modules.

**Architecture:** Add microvm.nix as flake input, create microvm-specific modules, expose `microvm.nixosConfigurations.dev-vm` output that composes existing modules with microvm guest configuration.

**Tech Stack:** Nix Flakes, microvm.nix, cloud-hypervisor, virtiofs

---

## Task 1: Add microvm.nix Flake Input

**Files:**
- Modify: `flake.nix:1-25` (inputs section)

**Step 1: Add microvm input to flake.nix**

In `flake.nix`, add the microvm input after the existing inputs (around line 22, before `superpowers`):

```nix
    microvm.url = "github:astro/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
```

**Step 2: Add microvm to outputs function parameters**

In `flake.nix`, add `microvm` to the outputs function parameters (around line 36):

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
    microvm,
    ...
  }: let
```

**Step 3: Validate the flake still parses**

Run: `nix flake check --no-build`
Expected: No errors (warnings OK)

**Step 4: Commit**

```bash
git add flake.nix
git commit -m "feat(microvm): add microvm.nix flake input"
```

---

## Task 2: Create Microvm Platform Configuration

**Files:**
- Create: `os/microvm.nix`

**Step 1: Create the microvm platform configuration**

Create `os/microvm.nix` with minimal NixOS config suitable for VM guests (no bootloader, minimal services):

```nix
# Microvm platform configuration
# Similar to os/nixos.nix but stripped down for VM guests
{lib, ...}: {
  # Microvms don't need traditional boot configuration
  # microvm.nix handles kernel/initrd directly

  # Select internationalisation properties
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable flakes
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Disable documentation to reduce closure size
  documentation.enable = lib.mkDefault false;
  documentation.man.enable = lib.mkDefault false;
  documentation.nixos.enable = lib.mkDefault false;

  # Minimal system - no X11
  services.xserver.enable = lib.mkDefault false;
}
```

**Step 2: Validate syntax**

Run: `nix-instantiate --parse os/microvm.nix`
Expected: No syntax errors

**Step 3: Commit**

```bash
git add os/microvm.nix
git commit -m "feat(microvm): add microvm platform configuration"
```

---

## Task 3: Create Microvm Guest Module

**Files:**
- Create: `modules/microvm/default.nix`

**Step 1: Create the microvm module directory**

Run: `mkdir -p modules/microvm`
Expected: Directory created

**Step 2: Create the main microvm module**

Create `modules/microvm/default.nix` with the microvm.nix integration:

```nix
# Microvm module - integrates microvm.nix with our configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Import microvm.nix NixOS module (provided by flake)
  # The actual import happens in flake.nix via microvm.nixosModules.microvm

  microvm = {
    # Use cloud-hypervisor for good performance
    hypervisor = "cloud-hypervisor";

    # Resource allocation
    mem = 4096; # 4GB RAM
    vcpu = 4;

    # Use virtiofs for shared directories (fast, modern)
    shares = [
      {
        tag = "project";
        source = "/tmp/microvm-share";
        mountPoint = "/mnt/project";
        proto = "virtiofs";
      }
    ];

    # Networking - user-mode NAT (no root required)
    interfaces = [
      {
        type = "user";
        id = "eth0";
        mac = "02:00:00:00:00:01";
      }
    ];

    # Use tmpfs for root (ephemeral)
    volumes = [];
  };

  # Guest networking configuration
  networking = {
    hostName = lib.mkDefault "dev-vm";
    useDHCP = true;
    firewall.enable = false; # Trust host
  };

  # Enable SSH for easy access
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Set root password for easy access (development only!)
  users.users.root.password = "dev";

  # Minimal packages for guest
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
  ];

  # System state version
  system.stateVersion = "25.05";
}
```

**Step 3: Validate syntax**

Run: `nix-instantiate --parse modules/microvm/default.nix`
Expected: No syntax errors

**Step 4: Commit**

```bash
git add modules/microvm/
git commit -m "feat(microvm): add microvm guest module"
```

---

## Task 4: Create dev-vm Target Configuration

**Files:**
- Create: `targets/microvms/dev-vm.nix`

**Step 1: Create targets/microvms directory**

Run: `mkdir -p targets/microvms`
Expected: Directory created

**Step 2: Create the dev-vm target**

Create `targets/microvms/dev-vm.nix` with VM-specific settings:

```nix
# dev-vm target configuration
# Development environment in a microvm
{pkgs, ...}: {
  # Override hostname
  networking.hostName = "dev-vm";

  # Create development user (matching host user pattern)
  users.users.dev = {
    isNormalUser = true;
    description = "Development User";
    extraGroups = ["wheel"];
    shell = pkgs.zsh;
    home = "/home/dev";
    password = "dev"; # Simple password for dev VM
  };

  # Ensure zsh is available
  programs.zsh.enable = true;

  # Allow passwordless sudo for dev user
  security.sudo.wheelNeedsPassword = false;

  # Time zone
  time.timeZone = "America/New_York";
}
```

**Step 3: Validate syntax**

Run: `nix-instantiate --parse targets/microvms/dev-vm.nix`
Expected: No syntax errors

**Step 4: Commit**

```bash
git add targets/microvms/
git commit -m "feat(microvm): add dev-vm target configuration"
```

---

## Task 5: Add Microvm Output to Flake

**Files:**
- Modify: `flake.nix:125-215` (outputs section)

**Step 1: Add mkMicrovm helper function**

In `flake.nix`, add the helper function after `commonModules` definition (around line 129):

```nix
    # Helper to create microvm configuration
    mkMicrovm = name: roles:
      microvm.lib.nixosSystem {
        system = "x86_64-linux";
        modules =
          [
            microvm.nixosModules.microvm
            configuration
          ]
          ++ commonModules
          ++ [
            ./os/microvm.nix
            ./modules/microvm
            ./targets/microvms/${name}.nix
            (mkBundleModule "linux" roles)
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              myConfig = {
                users = [
                  {
                    name = "dev";
                    email = "dev@localhost";
                    fullName = "Development User";
                    isAdmin = true;
                    sshIncludes = [];
                  }
                ];
                development.enable = true;
                agent-skills.enable = false;
                onepassword.enable = false;
              };
            }
          ];
      };
```

**Step 2: Add microvm output**

In `flake.nix`, add the microvm output after `nixosConfigurations` (around line 213, before the final closing braces):

```nix
    # Microvm configurations
    microvm.nixosConfigurations = {
      dev-vm = mkMicrovm "dev-vm" ["developer"];
    };
```

**Step 3: Validate the flake**

Run: `nix flake check --no-build`
Expected: No errors

**Step 4: Test microvm configuration evaluates**

Run: `nix eval .#microvm.nixosConfigurations.dev-vm.config.system.build.toplevel --json 2>&1 | head -1`
Expected: JSON output (store path) or evaluation starts

**Step 5: Commit**

```bash
git add flake.nix
git commit -m "feat(microvm): add microvm flake output with dev-vm"
```

---

## Task 6: Add Taskfile Automation

**Files:**
- Modify: `Taskfile.yml`

**Step 1: Add microvm tasks to Taskfile.yml**

Add the following tasks at the end of `Taskfile.yml` (before the final empty line):

```yaml
  microvm:build:
    desc: Build microvm image
    cmd: |
      echo "Building dev-vm microvm..."
      nix build .#microvm.nixosConfigurations.dev-vm.config.microvm.declaredRunner -o result-microvm
      echo "Build complete: ./result-microvm"
  microvm:run:
    desc: Run dev-vm microvm
    cmd: |
      if [[ "$(uname)" == "Darwin" ]]; then
        echo "macOS detected - microvm.nix requires Linux/KVM"
        echo "Please run from a Linux host or inside Colima"
        echo ""
        echo "To run in Colima:"
        echo "  1. colima start --arch x86_64 --vm-type vz"
        echo "  2. colima ssh"
        echo "  3. cd /path/to/nix && task microvm:run"
        exit 1
      fi
      echo "Starting dev-vm microvm..."
      nix run .#microvm.nixosConfigurations.dev-vm.config.microvm.declaredRunner
  microvm:test:
    desc: Validate microvm configuration
    cmd: |
      echo "Validating dev-vm microvm configuration..."
      if nix eval .#microvm.nixosConfigurations.dev-vm.config.system.build.toplevel \
        --json >/dev/null 2>&1; then
        echo "dev-vm configuration valid"
      else
        echo "dev-vm configuration invalid"
        nix eval .#microvm.nixosConfigurations.dev-vm.config.system.build.toplevel \
          --json --show-trace
        exit 1
      fi
```

**Step 2: Validate Taskfile syntax**

Run: `task --list | grep microvm`
Expected: Shows microvm:build, microvm:run, microvm:test

**Step 3: Commit**

```bash
git add Taskfile.yml
git commit -m "feat(microvm): add task automation for microvm"
```

---

## Task 7: Update Test Tasks

**Files:**
- Modify: `Taskfile.yml`

**Step 1: Add microvm to test:quick task**

In `Taskfile.yml`, find the `test:quick` task and add microvm validation. After the Darwin configurations loop (around line 88), add:

```yaml
          # Test microvm configuration
          echo "Testing dev-vm microvm configuration..."
          if nix eval .#microvm.nixosConfigurations.dev-vm.config.system.build.toplevel \
            --json >/dev/null 2>&1; then
            echo "Microvm dev-vm configuration valid"
          else
            echo "Microvm dev-vm configuration invalid"
            failed_checks="$failed_checks microvm:dev-vm"
          fi
```

**Step 2: Validate Taskfile syntax**

Run: `task --list`
Expected: No errors

**Step 3: Run quick test to verify**

Run: `task test:quick`
Expected: Includes microvm validation (may fail initially, that's OK)

**Step 4: Commit**

```bash
git add Taskfile.yml
git commit -m "feat(microvm): add microvm to test:quick validation"
```

---

## Task 8: Final Validation

**Step 1: Run full test suite**

Run: `task test:quick`
Expected: All checks pass including microvm

**Step 2: Build microvm (on Linux or skip)**

Run (Linux only): `task microvm:build`
Expected: Builds successfully, creates `./result-microvm`

**Step 3: Format and lint**

Run: `task quality`
Expected: All checks pass

**Step 4: Final commit if any formatting changes**

```bash
git add -A
git commit -m "style: format microvm configuration files" || echo "Nothing to commit"
```

---

## Summary

After completing all tasks, you will have:

1. **Flake input:** `microvm` from github:astro/microvm.nix
2. **Platform config:** `os/microvm.nix` (minimal NixOS for VMs)
3. **Module:** `modules/microvm/default.nix` (microvm.nix integration)
4. **Target:** `targets/microvms/dev-vm.nix` (dev VM settings)
5. **Flake output:** `microvm.nixosConfigurations.dev-vm`
6. **Tasks:** `microvm:build`, `microvm:run`, `microvm:test`

**To use:**
- Build: `task microvm:build`
- Run (Linux): `task microvm:run`
- Test: `task microvm:test`
