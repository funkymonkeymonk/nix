---
name: devenv
description: Use when working with devenv developer environments. Covers setup, packages, scripts, tasks, processes, services, git-hooks, and file generation. Use when initializing devenv, adding packages, configuring services like postgres/redis, running processes, or troubleshooting devenv issues.
---

# Devenv Developer Environments

## Overview

Devenv provides fast, declarative, reproducible developer environments using Nix. Configuration lives in `devenv.nix` with inputs defined in `devenv.yaml`.

**Core principle:** Everything is configured in `devenv.nix`, state persists in `.devenv/state/`, runtime files live in `$DEVENV_RUNTIME`.

## Quick Reference

| Task | Command |
|------|---------|
| Initialize new project | `devenv init` |
| Enter shell | `devenv shell` |
| Start processes | `devenv up` (foreground) / `devenv up -d` (background) |
| Stop processes | `devenv processes down` |
| Run tasks | `devenv tasks run <task>` |
| Search packages | `devenv search <name>` |
| Update inputs | `devenv update` |
| Run tests | `devenv test` |
| Get info | `devenv info` |
| Garbage collect | `devenv gc` |

## Key Files

| File | Purpose |
|------|---------|
| `devenv.nix` | Main configuration (required) |
| `devenv.yaml` | Inputs and imports |
| `devenv.lock` | Pinned input versions |
| `devenv.local.nix` | Local overrides (not committed) |
| `.envrc` | direnv integration |

## Environment Variables

```bash
$DEVENV_ROOT      # Project root (where devenv.nix lives)
$DEVENV_DOTFILE   # .devenv directory
$DEVENV_STATE     # Persistent state (.devenv/state)
$DEVENV_RUNTIME   # Runtime files (sockets, PIDs)
$DEVENV_PROFILE   # Nix store path for profile
```

## Topic Guides

This skill includes detailed guides for specific topics:

- **basics.md** - Installation, setup, updating, direnv integration
- **packages.md** - Adding packages and searching nixpkgs
- **scripts.md** - Defining custom scripts
- **tasks.md** - Task dependencies, inputs/outputs, file watching
- **processes.md** - Process management, logs, status monitoring
- **services.md** - Pre-configured services (postgres, redis, etc.)
- **files.md** - Generating config files (JSON, YAML, TOML, etc.)
- **git-hooks.md** - Pre-commit hooks via git-hooks.nix

## Minimal devenv.nix Example

```nix
{ pkgs, ... }:

{
  # Packages available in shell
  packages = [ pkgs.git pkgs.jq ];

  # Language support
  languages.python.enable = true;

  # Custom scripts
  scripts.hello.exec = ''echo "Hello from devenv!"'';

  # Services
  services.postgres.enable = true;

  # Processes
  processes.server.exec = "python -m http.server";

  # Git hooks
  git-hooks.hooks.shellcheck.enable = true;

  # Shell entry
  enterShell = ''
    echo "Welcome to the dev environment"
  '';
}
```

## Common Workflows

### Adding a Package

```bash
# Search for package
devenv search ncdu

# Add to devenv.nix
packages = [ pkgs.ncdu ];
```

### Enabling a Service

```nix
# In devenv.nix
services.postgres = {
  enable = true;
  initialDatabases = [{ name = "mydb"; }];
};
```

Then run `devenv up` to start.

### Creating a Task

```nix
tasks."build:app" = {
  exec = "npm run build";
  before = [ "devenv:enterShell" ];  # Run on shell entry
};
```

### Checking What's Configured

```bash
# See full environment info
devenv info

# Grep devenv.nix for specifics
grep -E "services\.|processes\.|packages" devenv.nix
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Shell not activating | Run `devenv shell` manually |
| Service won't start | Delete `$DEVENV_STATE/<service>/` and retry |
| Packages not found | Run `devenv update` to refresh inputs |
| direnv not loading | Run `direnv allow` in project |
| Old cached config | Use `--refresh-eval-cache` flag |

## References

- Full options: https://devenv.sh/reference/options/
- Examples: https://devenv.sh/examples/
- Languages: https://devenv.sh/languages/
