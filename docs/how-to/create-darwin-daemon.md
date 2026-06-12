---
title: "Create a Darwin System Daemon"
description: "How to create a new launchd system daemon service for macOS machines"
type: how-to
audience: both
last-reviewed: 2026-06-13
---

# Create a Darwin System Daemon

This guide shows you how to add a new background service to macOS machines managed by this repo.

## Daemons vs Agents

nix-darwin exposes two launchd scopes:

| Scope | Location | Runs as | When | Use for |
|-------|----------|---------|------|---------|
| `launchd.daemons` | `/Library/LaunchDaemons/` | root (or `UserName`) | System boot | Server processes, LLM inference, databases |
| `launchd.agents` | `~/Library/LaunchAgents/` | The user | User login | Menu bar apps, per-user tools |

**This repo prefers `launchd.daemons`.** System daemons:

- Start at boot, before any user logs in
- Survive logout/login cycles
- Work correctly with `KeepAlive`
- Have predictable `/tmp` log paths visible to all users
- Integrate cleanly with nix-darwin's `launchd` module

Use `UserName` and `GroupName` to run the daemon as a specific user rather than root, so file ownership (caches, configs, models) stays correct:

```nix
launchd.daemons.my-service = {
  serviceConfig = {
    UserName = "monkey";
    GroupName = "staff";
    # ...
  };
};
```

## Step 1: Create the Options

Add your service's configuration options to `modules/common/options.nix` under `myConfig`:

```nix
my-service = {
  enable = mkOption {
    type = types.bool;
    default = false;
    description = "Enable my-service";
  };

  server = {
    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Bind address";
    };
    port = mkOption {
      type = types.port;
      default = 9000;
      description = "Bind port";
    };
  };
};
```

## Step 2: Create the Service Module

Create `modules/services/<name>/darwin.nix` using the standard pattern:

```nix
# modules/services/my-service/darwin.nix
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.my-service;

  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "monkey";
in {
  config = mkIf cfg.enable {
    launchd.daemons.my-service = {
      serviceConfig = {
        Label = "org.my-service";
        ProgramArguments = [
          "${pkgs.my-package}/bin/my-binary"
          "--host"
          cfg.server.host
          "--port"
          (toString cfg.server.port)
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/my-service.log";
        StandardErrorPath = "/tmp/my-service.err";
        UserName = primaryUser;
        GroupName = "staff";
      };
    };
  };
}
```

**Required serviceConfig fields:**

| Field | Purpose |
|-------|---------|
| `Label` | Unique reverse-domain identifier (e.g. `org.vmlx.server`) |
| `ProgramArguments` | Binary path and arguments as a list |
| `RunAtLoad` | Start immediately when the plist is loaded |
| `KeepAlive` | Restart the process if it exits |

## Step 3: Import in flake.nix

Add the module to the MegamanX target's `darwinModules`:

```nix
{
  darwinModules = [
    # ...
    ./modules/services/my-service/darwin.nix
  ];
}
```

## Step 4: Enable on a Target

Enable the service in the target configuration:

```nix
myConfig.my-service = {
  enable = true;
  server = {
    host = "0.0.0.0";
    port = 9000;
  };
};
```

## Step 5: Add Tests

Create `tests/test-my-service.nix` to validate option defaults and custom values. Follow the pattern in `tests/test-vmlx.nix`.

## Step 6: Run Checks

```bash
devenv tasks run check:lint
nix build .#darwinConfigurations.MegamanX.system --impure --no-link
```

## Common Patterns

### Running as the User (Not Root)

Always set `UserName` and `GroupName` so the daemon writes files with correct ownership:

```nix
launchd.daemons.my-service = {
  serviceConfig = {
    UserName = primaryUser;
    GroupName = "staff";
  };
};
```

This avoids root-owned files in `~/.cache/`, `~/.config/`, or `~/.local/`.

### Self-Bootstrapping Services

For services that install via external tools (e.g. `uv`, `pip`), use a wrapper script that bootstraps on first run:

```nix
myWrapper = pkgs.writeShellScriptBin "my-service-bootstrap" ''
  if [ ! -x "${userBin}" ]; then
    ${pkgs.uv}/bin/uv tool install my-package
  fi
  exec ${userBin} serve --port ${toString cfg.server.port}
'';
```

The wrapper handles installation at service-start time, not at switch time, avoiding permission issues with activation scripts.

### Optional Arguments

Use `lib.optional` and `lib.optionalString` for conditional flags:

```nix
ProgramArguments =
  [ "${pkgs.my-package}/bin/my-binary" ]
  ++ optional cfg.enableFeature "--feature-flag"
  ++ optional (cfg.value != null) "--value"
  ++ optional (cfg.value != null) (toString cfg.value);
```

### Logging

Write logs to `/tmp/<service>.log` and errors to `/tmp/<service>.err`. These are ephemeral (cleared on reboot) and avoid filling the user's home directory.

> **See also:** [Architecture](../explanation/architecture.md) for module structure, [Options Reference](../reference/options.md) for option types.
