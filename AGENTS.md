---
title: "Agents Guide"
description: "Complete guide for AI agents working with this Nix system configuration repository. Includes testing, workflows, and MicroVM automation."
type: reference
audience: agent
last-reviewed: 2026-04-06
---

# Agents Guide

Guide for AI agents working with this Nix system configuration repository.

<!-- LLM: This document is optimized for AI agent consumption -->

## Quick Reference

| Task | Command |
|------|---------|
| Run lint check | `devenv tasks run check:lint` |
| Test Darwin configs | `devenv tasks run test:darwin-eval` |
| Test NixOS configs | `devenv tasks run test:nixos-eval` |
| Run all tests | `devenv tasks run test:all` |
| Full validation | `devenv tasks run check:all` |

---

## Repository Overview

This repository manages the configuration of computers via Nix flakes. **Agents should only modify Nix configuration files - never directly change computer configurations.**

## Architecture

- **Modules**: Reusable configuration logic (`modules/`)
- **Roles**: Modular role configurations (`modules/roles/`)
- **Targets**: Machine-specific configurations (`targets/`)
- **Options**: Type-safe configuration (`modules/common/options.nix`)

## Directory Structure

```
.
├── .github/                    # GitHub Actions workflows
├── modules/
│   ├── common/                 # Shared: options, users, shell, onepassword
│   ├── home-manager/           # User environment
│   │   └── skills/             # Agent skills management
│   ├── roles/                  # Role modules (one per role)
│   ├── services/               # Service modules (ollama, openclaw, matrix)
│   ├── microvm/                # MicroVM guest configuration
│   └── nixos/                  # Linux-specific modules
├── targets/                    # Machine configurations
│   └── microvms/               # MicroVM definitions (dev-vm, openclaw, matrix)
├── docs/                       # Documentation (Diataxis framework)
├── os/                         # Platform OS configurations
├── flake.nix                   # Main flake with helpers
└── devenv.nix                  # Tasks and dev environment
```

---

## Tasks

```bash
devenv tasks list              # List all tasks
devenv tasks run <task>        # Run a task
```

### Key Tasks

| Task | Description |
|------|-------------|
| `check:all` | Run all checks (lint + platform builds) |
| `check:lint` | Lint only |
| `build:darwin` | Build Darwin configurations (dry-run) |
| `build:nixos` | Build NixOS configurations (dry-run) |
| `system:switch` | Apply configuration |

### Shell Aliases

| Alias | Task |
|-------|------|
| `s` | `system:switch` |
| `q` | `check:all` |
| `b` | `build:all` |
| `i` | `dev:ide` |

### JJ Workspace Support

When working in a jj workspace (created with `jj workspace add` or `fjj`), the switch command is workspace-aware:

```bash
# From any workspace directory - automatically runs from repo root
s
switch
q
b
```

**How it works:**
- Detects if you're in a workspace (has `.jj/repo` as a file, not directory)
- Displays: `📁 JJ Workspace: <name>` and `Switch will run from: <repo-root>`
- Runs the command from the main repo root using your workspace's current commit

**Requirements:**
- Commit changes with `jj describe` before switching
- The switch uses your current jj commit
- Uncommitted changes are NOT included (use `scripts/switch-workspace-override` to test them)

This solves the Nix flake "untracked files" error when running from workspaces.

---

## Working with This Repository

### Testing Best Practices (CRITICAL)

**Always test locally before pushing to CI.** This catches errors early and saves time:

#### Required Local Tests (Run These Before Every Push)

```bash
# 1. Fast lint check (catches formatting and syntax errors)
devenv tasks run check:lint

# 2. Test Darwin configs can be evaluated (catches module errors)
# Run this on macOS - it validates all Darwin configurations without building
devenv tasks run test:darwin-eval

# 3. Test NixOS configs can be evaluated (catches module errors)
# Run this on any platform - validates module structure without full builds
devenv tasks run test:nixos-eval

# 4. Run all foundation tests
devenv tasks run test:all
```

#### What These Tests Catch

| Test | Catches |
|------|---------|
| `check:lint` | Formatting errors, dead code, syntax issues |
| `test:darwin-eval` | Missing options on Darwin (e.g., `programs.zoxide`), module import errors |
| `test:nixos-eval` | Missing options on NixOS (e.g., `home-manager.users`), module import errors |
| `test:all` | Package availability, option definitions |

#### Common Module Errors to Avoid

1. **Platform-Specific Options**: Options like `programs.zoxide` or `environment.sessionVariables` don't exist on all platforms. Check if options exist before using them:
   ```nix
   # Good: Check if option exists
   config = lib.optionalAttrs (builtins.hasAttr "zoxide" options.programs) {
     programs.zoxide.enable = true;
   };
   
   # Bad: Assumes option exists everywhere
   programs.zoxide.enable = true;
   ```

2. **home-manager References**: Don't reference `home-manager` options when home-manager module isn't imported:
   ```nix
   # Good: Guard home-manager config
   homeManagerAvailable = builtins.hasAttr "home-manager" options;
   config = lib.mkIf homeManagerAvailable {
     home-manager.users = ...;
   };
   ```

3. **Using pkgs in let bindings**: This can cause infinite recursion. Use `config.myConfig.isDarwin` instead of checking `pkgs.stdenv.hostPlatform`.

### Before Changes
1. Run `devenv tasks run check:lint` for fast feedback
2. Run platform-specific eval tests (`test:darwin-eval` or `test:nixos-eval`)
3. Use `devenv shell` for proper tooling

### Making Changes
1. Modify files as needed
2. Run local tests (lint + platform eval tests)
3. Run `devenv tasks run check:all` for validation
4. Commit with conventional commit messages

---

## Test-Driven Development (TDD) Workflow

This repository follows TDD principles. **Write tests before implementation.**

### TDD Cycle

```
┌─────────────────┐
│  1. Write Test  │ ← Start here: Define expected behavior
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. See it Fail  │ ← Run test, confirm it fails (RED)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. Implement    │ ← Write minimal code to pass
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 4. See it Pass  │ ← Run test, confirm it passes (GREEN)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 5. Refactor     │ ← Clean up, improve, optimize
└─────────────────┘
```

### TDD Example: Adding a New MicroVM

**Step 1: Write the test first**

```bash
# Create test file tests/test-microvm.nix with tests for your new VM
# Test hostname, services, ports, etc.
```

**Step 2: Add test to test suite**

```nix
# In tests/default.nix, add your test:
my-microvm-config = testMicrovm.myMicrovmConfigTest;
```

**Step 3: Run test - it should fail**

```bash
# This will fail because the MicroVM doesn't exist yet
nix build .#checks.x86_64-linux.my-microvm-config
```

**Step 4: Implement the MicroVM**

```nix
# Create targets/microvms/my-microvm.nix
# Add to flake.nix microvm.nixosConfigurations
```

**Step 5: Run test - it should pass**

```bash
# Now the test should pass
nix build .#checks.x86_64-linux.my-microvm-config
```

### Test Types to Write

| Type | Location | When to Write | Example |
|------|----------|---------------|---------|
| **Config Test** | `tests/test-*.nix` | Before adding new module | Test hostname, IP, basic options |
| **Service Test** | `tests/test-*.nix` | Before enabling services | Test `services.x.enable = true` |
| **Firewall Test** | `tests/test-*.nix` | Before opening ports | Test `allowedTCPPorts` contains expected ports |
| **Integration Test** | `tests/vm/*.nix` | Before full feature | Boot VM, test actual service behavior |
| **Eval Test** | `devenv task` | Always | `test:nixos-eval`, `test:darwin-eval` |

### Test Helper Functions

Use these helpers from `pkgs.lib`:

```nix
# Assert equality
assertEq = name: expected: actual:
  if actual == expected
  then "${name}: OK"
  else throw "${name}: expected ${toString expected}, got ${toString actual}";

# Assert list contains value  
assertContains = name: value: list:
  if builtins.elem value list
  then "${name}: OK"
  else throw "${name}: list missing ${toString value}";
```

### Running Specific Tests

```bash
# Run all checks
nix flake check

# Run specific check
nix build .#checks.x86_64-linux.microvm-config --no-link

# Run all tests via devenv
devenv tasks run test:all

# Run eval tests only
devenv tasks run test:nixos-eval
```

### TDD Checklist

Before marking a task complete:

- [ ] Tests written BEFORE implementation
- [ ] Test fails before implementation (RED phase verified)
- [ ] Minimal implementation to make test pass (GREEN phase)
- [ ] Refactoring complete without breaking tests
- [ ] All existing tests still pass
- [ ] CI checks pass (`check:lint`, `test:all`)

### Adding Features

| Feature | Steps |
|---------|-------|
| New Machine | Create `targets/<name>/`, add to `flake.nix` |
| New Role | Create `modules/roles/<name>.nix`, add enable option to `modules/common/options.nix` |
| New Module | Create in `modules/` subdirectory |
| New Option | Add to `modules/common/options.nix` |

---

## Roles (modules/roles/)

| Role | Description |
|------|-------------|
| `base` | Essential packages and shell |
| `developer` | Development tools |
| `creative` | Media tools |
| `desktop` | Desktop applications |
| `workstation` | Work tools |
| `entertainment` | Entertainment apps |
| `gaming` | Gaming tools |
| `agent-skills` | AI skills management |
| `opencode` | OpenCode + rtk |
| `claude` | Claude Code + rtk |
| `pi` | Pi coding agent + rtk |
| `llm-host` | Ollama |

---

## Helper Functions (flake.nix)

| Helper | Purpose |
|--------|---------|
| `mkUser` | Create user configuration with defaults |
| `mkNixHomebrew` | Create homebrew config for Darwin |
| `mkMicrovm` | Create microvm configuration |

---

## Agent Skills

Skills auto-install when roles like `developer`, `opencode`, or `claude` are active.

**Location:** `~/.config/opencode/skills/`

### Adding Skills

1. Create `modules/home-manager/skills/internal/skill-name/SKILL.md`
2. Register in `modules/home-manager/skills/manifest.nix`
3. Rebuild system

---

## MicroVM Automation for Agents

<!-- LLM: This section is for deploying yourself in a MicroVM -->

### Automated OpenCode Deployment

If you need to deploy OpenCode (or yourself) in a MicroVM, use the automation guide:

**Document:** [Set Up OpenClaw MicroVM (Automated)](docs/how-to/setup-openclaw-microvm-automated.md)

**Key features for agents:**
- Cloud-init based configuration (no interactive prompts)
- Verification at each step
- No 1Password or Matrix required for basic setup
- Clear preconditions and error handling

### Quick Deployment

```bash
# From a NixOS host with MicroVM support:

# 1. Create cloud-init configuration
sudo tee /etc/cloud-init.yaml << 'EOF'
#cloud-config
hostname: opencode-vm
ssh_authorized_keys:
  - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIIxGvpCUmx1UV3K22/+sWLdRknZmlTmQgckoAUCApF8
nix:
  target: type-server
  flake: github:funkymonkeymonk/nix
  roles:
    - opencode
microvms:
  - name: opencode
    flake: .#microvm.nixosConfigurations.openclaw
    ipAddress: 192.168.83.16
    autoStart: true
EOF

# 2. Build and run
cd ~/nix
nix run .#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure

# 3. Verify
ssh root@192.168.83.16 "systemctl is-active opencode-gateway"
```

### Cloud-Init Tool

The repository includes `nix-cloud-init` for managing cloud-init configurations:

```bash
# Interactive setup (requires gum)
sudo nix-cloud-init init

# Automated setup
sudo nix-cloud-init set hostname opencode-vm
sudo nix-cloud-init set target type-server
sudo nix-cloud-init validate

# MicroVM management
sudo nix-cloud-init microvm add opencode .#microvm.nixosConfigurations.openclaw 192.168.83.16
sudo nix-cloud-init microvm generate
```

See the full guide for complete automation details.

---

## Jujutsu (jj) Version Control

If `.jj/` directory exists:
1. Use `jj` skill for all version control
2. Run `jj status` before any operation
3. Use `jj new` before starting work
4. Use `jj describe` for commit messages
5. Never mix git and jj commands

### Commit-First Workflow (Required)

**This repository does NOT use `allow-dirty`** - Nix flakes require a clean git state.

**Why:** The flake reads files from git HEAD, not the working copy. JJ's colocation with git can cause issues when parent commits have conflicts (jj stores conflicts specially that git can't read).

**Workflow:**
```bash
# 1. Make your changes
# 2. Commit them with jj
jj describe -m "feat: your changes"

# 3. NOW run nix commands
nix build .#target
# or
devenv tasks run check:all
```

**If you must test before committing**, use `--impure`:
```bash
nix build .#target --impure
```

**Never use `--impure` for final validation** - always commit first and test without it.

---

## Platform Support

- **macOS**: nix-darwin (aarch64-darwin)
- **Linux**: NixOS (x86_64-linux)

### Cross-Platform Validation

Tests are platform-specific:
- `test:darwin` on macOS
- `test:nixos` on Linux

CI runs both on separate runners.

---

## NixOS Rebuild Commands

When deploying to NixOS systems:

```bash
# Standard rebuild (always use --impure for non-CI environments)
sudo nixos-rebuild switch --flake github:funkymonkeymonk/nix#<hostname> --impure

# Example for type-server
sudo nixos-rebuild switch --flake github:funkymonkeymonk/nix#type-server --impure
```

**Important**: Always use `--impure` flag for manual deployments. This repository uses nixos-facter for hardware detection and disposable environments that require impure evaluation. Only CI uses pure evaluation.

---

## Code Style

- Use alejandra formatter (`quality:check`)
- Remove dead code (deadnix)
- Follow existing patterns
- Conventional commits: `feat:`, `fix:`, `docs:`

---

## RTK Token Optimization

Use RTK-prefixed commands for token-efficient output:

| Standard | RTK | Savings |
|----------|-----|---------|
| `git status` | `rtk git status` | ~80% |
| `git diff` | `rtk git diff` | ~75% |
| `git log` | `rtk git log` | ~80% |

Check savings: `rtk gain`

---

## Documentation for Agents

### Diataxis Framework

Documentation is organized by type:

| Type | Location | Use When |
|------|----------|----------|
| Tutorials | `docs/tutorials/` | Learning something new |
| How-To Guides | `docs/how-to/` | Completing a specific task |
| Reference | `docs/reference/` | Looking up technical details |
| Explanation | `docs/explanation/` | Understanding how/why |

### Key Documents

- **[docs/index.md](docs/index.md)** - Documentation hub with navigation
- **[docs/how-to/setup-opencode-microvm-automated.md](docs/how-to/setup-opencode-microvm-automated.md)** - Automated deployment guide
- **[docs/reference/options.md](docs/reference/options.md)** - Configuration reference
- **[docs/explanation/architecture.md](docs/explanation/architecture.md)** - System architecture

<!-- LLM: END OF AGENTS GUIDE -->
