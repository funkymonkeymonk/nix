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

## Model Source

All MLX models should be sourced from [mlx-community collections](https://huggingface.co/mlx-community/collections).
Prefer models from the `mlx-community` org when adding new models to the configuration.
Check the collection for the latest MLX-converted models before choosing alternatives.

| Task | Command |
|------|---------|
| Run lint check | `devenv tasks run check:lint` |
| Run all tests | `devenv tasks run test` |
| Apply config | `devenv tasks run system:switch` |

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
| `check:lint` | Lint only |
| `test` | Run all foundation checks (eval + build) |
| `system:switch` | Apply configuration |

### Shell Aliases

| Alias | Task |
|-------|------|
| `s` | `system:switch` |

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

# 2. Run all foundation tests (eval + build checks, single flake evaluation)
devenv tasks run test
```

#### What These Tests Catch

| Test | Catches |
|------|---------|
| `check:lint` | Formatting errors, dead code, syntax issues |
| `test` | Eval errors on all platforms + package availability, option definitions |

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
2. Use `devenv shell` for proper tooling

### Making Changes
1. Modify files as needed
2. Run local tests (lint + foundation tests)
3. Commit with conventional commit messages

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
| **Eval Test** | `devenv task` | Always | `test` |

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
devenv tasks run test
```

### TDD Checklist

Before marking a task complete:

- [ ] Tests written BEFORE implementation
- [ ] Test fails before implementation (RED phase verified)
- [ ] Minimal implementation to make test pass (GREEN phase)
- [ ] Refactoring complete without breaking tests
- [ ] All existing tests still pass
- [ ] CI checks pass (`check:lint`, `test`)

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

### Workspace Workflow (Agents Must Use Workspaces)

Workspaces isolate each change in flight. **Agents MUST use workspaces for all non-trivial changes.**

#### Workspace Location

Workspaces live in `~/workspaces/` (not inside the repository as sibling directories):

```
~/workspaces/
  feat-auth-20260512-a1b2/     ← workspace directory
  fix-bug-20260512-c3d4/       ← another workspace
```

Use `fjj` to create workspaces from any directory:

```bash
fjj feat/my-topic              # Create workspace from main
fjj fix/bug-name develop       # Create workspace from develop
fjj list                       # Show all workspaces
fjj clean                      # Remove merged/stale workspaces
```

#### Agent Workspace Naming

Agent workspace names encode agent identity and purpose:

```
feat/agent-<agent-id>-<topic>     # e.g. feat/agent-openclaw-hostid-fix
fix/agent-<agent-id>-<topic>      # e.g. fix/agent-openclaw-lint-error
```

This lets humans distinguish agent workspaces from human workspaces at a glance.

#### Example Workflow: Create → Work → Finish → Clean

```bash
# 1. Create workspace (stored in ~/workspaces/, NOT in repo)
fjj feat/agent-openclaw-my-feature

# 2. cd into the workspace
cd ~/workspaces/feat-agent-openclaw-my-feature-<date>-<id>

# 3. Work and commit (the working copy IS a commit — no git add needed)
# ... make changes ...
jj describe -m "feat: add my feature"

# 4. Validate from repo root (devenv tasks require repo root)
cd /path/to/repo && devenv tasks run check:lint

# 5. Push and create PR (from workspace dir)
cd ~/workspaces/feat-agent-openclaw-my-feature-<date>-<id>
jj bookmark set feat/my-feature -r @
jj git push --bookmark feat/my-feature
gh pr create --head feat/my-feature

# 6. After PR is merged: clean up
jj workspace forget feat-agent-openclaw-my-feature-<date>-<id>
rm -rf ~/workspaces/feat-agent-openclaw-my-feature-<date>-<id>
```

#### Session TTL

`jj-workspace-session` manages fast sync (every 5 min) during active sessions. Sessions auto-expire after 30 minutes of inactivity. Prune expired sessions with:

```bash
jj-workspace-session prune
jj-workspace-session status   # Show active sessions
```

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
devenv tasks run test
```

**If you must test before committing**, use `--impure`:
```bash
nix build .#target --impure
```

**Never use `--impure` for final validation** - always commit first and test without it.

---

## macOS Service Definitions (nix-darwin)

When defining launchd services on macOS, follow the upstream nix-darwin patterns. **Do not manually script `launchctl` commands in individual modules** — nix-darwin's activation scripts handle loading/unloading automatically.

### Daemon vs Agent

| Type | Nix Option | Runs As | Scope |
|------|-----------|---------|-------|
| **Daemon** | `launchd.daemons.<name>` | root or specified user | System-wide |
| **User Agent** | `launchd.user.agents.<name>` | Logged-in user | Per-user |

### Prefer `command` or `script`

Use the high-level `command` or `script` options. nix-darwin automatically wraps them with `/bin/wait4path /nix/store && exec …` and generates the correct `ProgramArguments`.

**Good — `command` for simple commands:**
```nix
launchd.daemons.myapp = {
  command = "${pkgs.myapp}/bin/myapp-server";
  serviceConfig.KeepAlive = true;
  serviceConfig.RunAtLoad = true;
};
```

**Good — `script` for setup + exec:**
```nix
launchd.daemons.myapp = {
  script = ''
    mkdir -p /var/lib/myapp
    printf '%s' "$CONFIG" > /var/lib/myapp/config.json
    exec ${pkgs.myapp}/bin/myapp-server
  '';
  serviceConfig.KeepAlive = true;
};
```

**Bad — manually wrapping `ProgramArguments`:**
```nix
# ❌ Anti-pattern: do not wrap scripts in ProgramArguments
launchd.daemons.myapp = {
  serviceConfig.ProgramArguments = [ "${pkgs.writeShellScript "myapp" ''...''}" ];
};
```

### When to Use `serviceConfig.ProgramArguments`

Only use the raw `ProgramArguments` plist key when you need precise argument-array semantics that `command` cannot express:
```nix
launchd.user.agents.skhd = {
  serviceConfig.ProgramArguments = [
    "${cfg.package}/bin/skhd"
    "-c" "/etc/skhdrc"
  ];
};
```

### Labels

nix-darwin auto-generates labels as `org.nixos.<name>`. **Only override `serviceConfig.Label` if external tools reference the specific label.**

```nix
# Default (preferred)
launchd.daemons.nix-daemon = {
  command = ...;
};
# → Label = org.nixos.nix-daemon

# Override only when needed externally
launchd.daemons.nix-daemon = {
  command = ...;
  serviceConfig.Label = "org.nixos.nix-daemon";  # Only if external scripts reference it
};
```

### Common `serviceConfig` Keys

```nix
launchd.daemons.myapp = {
  command = ...;
  serviceConfig = {
    KeepAlive = true;           # Restart on exit
    RunAtLoad = true;           # Start when loaded
    UserName = "myuser";        # Run as non-root
    WorkingDirectory = "/var/lib/myapp";
    StandardOutPath = "/var/log/myapp.log";
    StandardErrorPath = "/var/log/myapp.error.log";
    EnvironmentVariables = {
      HOME = "/var/lib/myapp";
    };
    ProcessType = "Background"; # Background | Standard | Adaptive | Interactive
  };
};
```

### Activation Scripts

**Do not** add per-service `launchctl list` status checks in `system.activationScripts`. nix-darwin already diffs plists, unloads old services, and loads new ones. If a custom bootstrap sequence is required (e.g., macOS Tahoe `launchctl load -w` workaround), centralize it in `modules/common/launchd-services.nix` rather than duplicating it across modules.

### Full Reference

- [nix-darwin launchd module](https://github.com/nix-darwin/nix-darwin/blob/master/modules/launchd/default.nix)
- [nix-darwin launchd plist options](https://github.com/nix-darwin/nix-darwin/blob/master/modules/launchd/launchd.nix)
- [Apple launchd.plist(5)](https://developer.apple.com/library/archive/documentation/Darwin/Reference/ManPages/man5/launchd.plist.5.html)

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

**Troubleshooting `op` (1Password CLI) hangs**: The `system:switch` task and `apply-config-to-microvms` script use `op` to fetch sudo passwords. If `op signin`, `op read`, or `op whoami` hang indefinitely, the CLI is likely waiting for browser-based authorization that requires the user to approve a 1Password prompt. Agents cannot complete this step — the user must sign in manually (e.g., `op signin` and approve the browser prompt). Once signed in, the CLI caches the session and subsequent `op` calls work without interaction.

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
