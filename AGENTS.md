---
title: "Agents Guide"
description: "Complete guide for AI agents working with this Nix system configuration repository. Includes testing and workflows."
type: reference
audience: agent
last-reviewed: 2026-09-27
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
| Run all tests | `devenv tasks run test:all` |
| Run eval only | `devenv tasks run test:eval` |
| Run build checks only | `devenv tasks run test:build-checks` |
| Apply config | `devenv tasks run system:switch` |

---

## Repository Overview

This repository manages the configuration of computers via Nix flakes. **Agents should only modify Nix configuration files - never directly change computer configurations.**

## Architecture

- **Modules**: Reusable configuration logic (`modules/`)
- **Roles**: Modular role configurations (`modules/roles/`)
- **Machines**: Per-machine configuration modules (`machines/`); machine metadata and composition live in `library/machines/catalog.nix
- **Options**: Type-safe configuration (`modules/common/options.nix`)

## Principles

**Do not document directory structures.** Agents reviewing code can use `ls`, `find`, or file exploration tools to traverse the codebase. Tree diagrams in documentation rot quickly and add noise. Document *concepts* and *relationships*, not folder listings.

### NixOS User Services

NixOS does not reliably restart changed `systemd.user.services` during a system switch. New graphical user services must use the existing Sunshine restart-bridge pattern, or introduce a shared helper once more than one NixOS module needs it. Restart bridges must reload the user manager, restart only when their service configuration changes, and guard on `graphical-session.target`; do not rely on manual restarts.

### 1Password Secret References

Machine-managed API keys and passwords must use the machine's `myConfig.onepassword.defaultVault`. Prefer an unqualified `Item/field` reference so the shared opnix helpers prepend `defaultVault`; do not hard-code another vault in a new target or role configuration. If a requested secret currently exists outside `defaultVault`, warn the user and ask them to move it or explicitly change the machine's default vault before wiring it into Nix. Do not silently create a cross-vault exception.

---

## Tasks

```bash
devenv tasks list              # List all tasks
devenv tasks run <task>        # Run a task
```

### Key Tasks

| Task | Description |
|------|-------------|
| `check:lint` | Lint only (alejandra + statix) |
| `test:all` | Run all tests (eval + build packages + build checks) |
| `test:eval` | Evaluate all NixOS/Darwin configurations |
| `test:build-packages` | Build package availability checks |
| `test:build-checks` | Build all runCommand eval tests |
| `system:switch` | Apply configuration |

### Shell Aliases

| Alias | Task |
|-------|------|
| `s` | `system:switch` |

### JJ Workspace Support

When working in a jj workspace created with `jj workspace add`, the switch command is workspace-aware:

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

**Agents MUST run these commands before pushing any changes to CI.**

```bash
# 1. Fast lint check (catches formatting and syntax errors) — ~10s
devenv tasks run check:lint

# 2. Run all foundation tests (eval + build checks) — ~60s
devenv tasks run test:all
```

**If you are short on time, run the minimum:**
```bash
# Minimum viable pre-push test — catches 90% of CI failures
devenv tasks run check:lint
devenv tasks run test:build-checks
```

#### What These Tests Catch

| Test | Catches |
|------|---------|
| `check:lint` | Formatting errors, dead code, syntax issues |
| `test:eval` | NixOS/Darwin configuration eval failures |
| `test:build-packages` | Missing packages, overlay breakages |
| `test:build-checks` | Module option errors, role config errors, missing imports |
| `test:all` | Everything above in one command |

#### Pre-Push Testing Checklist

Before creating a PR or pushing to a remote branch, agents MUST verify:

- [ ] `devenv tasks run check:lint` passes
- [ ] `devenv tasks run test:build-checks` passes (catches module eval failures)
- [ ] If you modified a NixOS or Darwin target: `devenv tasks run test:eval` passes

**Why this matters:** CI runs the exact same commands. A failure that takes 30 seconds to catch locally will take 10–40 minutes to surface in CI, blocking the PR and wasting compute.

#### Running Specific Checks

When you know what changed, run only the relevant check for faster feedback:

```bash
CURRENT_SYSTEM=$(nix eval --impure --expr 'builtins.currentSystem' --raw)

# Added a role? Test role config
nix build ".#checks.${CURRENT_SYSTEM}.all-role-tests" --no-link

# Added options? Test option definitions
nix build ".#checks.${CURRENT_SYSTEM}.foundation-options" --no-link

# Added a service module? Test service options
nix build ".#checks.${CURRENT_SYSTEM}.<service>-options" --no-link
```

List all available checks:
```bash
nix eval --json ".#checks.$(nix eval --impure --expr 'builtins.currentSystem' --raw)" | jq -r 'keys | sort | .[]'
```

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
2. **Run `devenv tasks run check:lint` after every meaningful change**
3. **Before committing, run `devenv tasks run test:build-checks`**
4. Commit with conventional commit messages

### Before Pushing (MANDATORY)
```bash
# Full validation — same suite CI runs
devenv tasks run check:lint
devenv tasks run test:all
```

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

### TDD Example: Adding a New Module Option

**Step 1: Write the test first**

```bash
# Create or extend a test file, e.g. tests/test-roles.nix
# Assert the new option's expected default and behavior
```

**Step 2: Add test to test suite**

```nix
# In tests/default.nix, add your test:
my-new-option = testRoles.myNewOptionTest;
```

**Step 3: Run test - it should fail**

```bash
# This will fail because the option doesn't exist yet
nix build .#checks.x86_64-linux.my-new-option
```

**Step 4: Implement the option**

```nix
# Add the option to the relevant modules/ file
# Wire up its config block
```

**Step 5: Run test - it should pass**

```bash
# Now the test should pass
nix build .#checks.x86_64-linux.my-new-option
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
nix build .#checks.aarch64-darwin.foundation-options --no-link

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

### Keeping Tests in Sync with Implementation

When you **remove** a package, option, or feature, the tests that asserted its presence will fail. You MUST update those tests in the same commit — this is not optional.

Common traps:

| Change You Make | Test File to Update | Field to Update |
|-----------------|---------------------|-----------------|
| Remove package from role | `tests/test-roles.nix` | `roleExpectedPackages.<role>` |
| Add package to role | `tests/test-roles.nix` | `roleExpectedPackages.<role>` |
| Change role cascade | `tests/test-roles.nix` | `roleCascades.<role>` |
| Remove service option | `tests/test-*.nix` | Any assertion referencing the option |

**Rule:** If `devenv tasks run test` fails after your change, you have not finished. Fix the tests before pushing.

### Adding Features

| Feature | Steps |
|---------|-------|
| New Machine | Create `machines/<name>/default.nix`, add its metadata and module stack to `library/machines/catalog.nix` |
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

---

## Helper Functions (flake.nix)

| Helper | Purpose |
|--------|---------|
| `mkUser` | Create user configuration with defaults |

---

## Agent Skills

The public `funkymonkeymonk/skills` repository is the source of standalone
agent skills. The Nix flake consumes it through the `personal-skills` input,
with its exact revision pinned in `flake.lock`.

When `developer`, `creative`, `workstation`, `opencode`, `claude`, or `pi` is
enabled, Home Manager installs complete skill directories under
`~/.agents/skills/`. OpenCode and Pi discover this location. Claude Code
receives the same repository-backed directories through its Home Manager module.

The Nix manifest contains optional metadata only. Do not add skill content or
install logic to this Nix repository. To change a skill, update the skills
repository, then run `nix flake update personal-skills` here and rebuild.

See `modules/home-manager/skills/README.md` for the install and update steps.

---

## Jujutsu (jj) Version Control

If `.jj/` directory exists:
1. Use native Jujutsu commands for version control
2. Run `jj status` before any operation
3. Use `jj new` before starting work
4. Use `jj describe` for commit messages
5. Never mix git and jj commands

### Workspace Workflow (Agents Must Use Workspaces)

Use native Jujutsu workspace commands. Keep workspaces under `~/workspaces/`.

```bash
jj workspace add --name feat-my-topic ~/workspaces/feat-my-topic
cd ~/workspaces/feat-my-topic
jj workspace list
```

Give each agent a separate workspace and bookmark. After work is complete,
forget the workspace and remove its directory:

```bash
jj workspace forget feat-my-topic
rm -rf ~/workspaces/feat-my-topic
```

This Nix flake does not install the former `jj-workspace` or fast-sync wrapper
scripts. Use the native `jj workspace`, `jj git`, and `gh` commands.

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

**New files require `git add` before they are visible to Nix flake eval.** `jj describe` only commits files already tracked by git. A file you just created will cause:

```
error: Path 'path/to/file.nix' in the repository "..." is not tracked by Git.
```

Fix by staging the file first, then committing:

```bash
git add path/to/new-file.nix
jj describe -m "feat: your changes"

# NOW run nix commands
nix build .#target
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

**Troubleshooting `op` (1Password CLI) hangs**: The `system:switch` task uses `op` to fetch sudo passwords. If `op signin`, `op read`, or `op whoami` hang indefinitely, the CLI is likely waiting for browser-based authorization that requires the user to approve a 1Password prompt. Agents cannot complete this step — the user must sign in manually (e.g., `op signin` and approve the browser prompt). Once signed in, the CLI caches the session and subsequent `op` calls work without interaction.

---

## Code Style

- Use alejandra formatter (`check:lint`)
- Remove dead code (deadnix)
- Follow existing patterns
- Conventional commits: `feat:`, `fix:`, `docs:`
- Do not leave tombstone comments when removing code — the user uses git history for that

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
- **[docs/reference/options.md](docs/reference/options.md)** - Configuration reference
- **[docs/explanation/architecture.md](docs/explanation/architecture.md)** - System architecture

<!-- LLM: END OF AGENTS GUIDE -->
