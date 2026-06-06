---
name: nix-darwin-launchd-debugging
description: >
  Use when a launchd service on nix-darwin fails to start, exits with
  non-zero status, or doesn't restart after a switch.
  Triggers on: exit code 78, "EX_CONFIG", "Operation not permitted",
  daemon vs user.agent decisions, plist not being reloaded.
---

# Nix-Darwin Launchd Debugging

## Overview

nix-darwin manages launchd plists via `launchd.daemons` and `launchd.user.agents`. Daemons auto-reload on switch; user agents don't. Exit code 78 (`EX_CONFIG`) usually means a path issue in the plist.

## Which Type to Use

```
Service needs to run as a specific user?
├── Yes → launchd.daemons + UserName
└── No → service should be system-level?
    ├── Yes → launchd.daemons (auto-managed by nix-darwin)
    └── No → launchd.user.agents (must be manually reloaded)
```

**Prefer `launchd.daemons` with `UserName`.** nix-darwin's activation script auto-unloads and reloads system daemons on every switch. User agents require `launchctl bootout` + `bootstrap` to take effect.

## Exit Codes

| Code | Name | Meaning | Likely Cause |
|------|------|---------|-------------|
| 78 | EX_CONFIG | Configuration error | `$HOME` or env var not expanded in plist path |
| 78 | EX_OSFILE | File not found | Binary or script path doesn't exist |
| 1 | — | Generic failure | Script `set -e` hit an error |
| 19968 | — | 78 × 256 wrapped | launchd stores exit codes × 256 |

## `$HOME` Expansion Trap

launchd does **not** expand environment variables in plist fields like `WorkingDirectory`, `ProgramArguments`, `StandardOutPath`, or `StandardErrorPath`.

```nix
# ❌ BROKEN — $HOME is literal, not expanded
WorkingDirectory = "$HOME/.local/share/my-service";

# ✅ CORRECT — use explicit path
WorkingDirectory = "/Users/monkey/.local/share/my-service";
```

In your nix-darwin module, use a computed home directory:

```nix
let
  primaryUser = (builtins.head config.myConfig.users).name;
  darwinHomeDir = "/Users/${primaryUser}";
in {
  launchd.daemons.my-service = {
    serviceConfig = {
      UserName = primaryUser;
      WorkingDirectory = "${darwinHomeDir}/.local/share/my-service";
    };
  };
}
```

Given that a user might not always be "monkey" if you're using actual users in the config. Use `builtins.head` to get the first user's name.

## Debugging Workflow

```bash
# 1. Check service status
launchctl print gui/501/com.my.service  # User agent
launchctl print system/com.my.service   # System daemon

# 2. Read the plist being used
cat ~/Library/LaunchAgents/com.my.service.plist

# 3. Run the Program script directly (bypass launchd)
bash /nix/store/xxx-my-service-launchd-script

# 4. Check for multiple generations of scripts
ls /nix/store/*-my-service-launchd-script

# 5. Reload the plist after a switch (user agents only)
launchctl unload ~/Library/LaunchAgents/com.my.service.plist
launchctl load ~/Library/LaunchAgents/com.my.service.plist
launchctl start com.my.service
```

## When the Switch Doesn't Restart

If the plist updated but the service is still running the old version:

| Domain | Auto-reloads on switch? | Manual reload |
|--------|------------------------|---------------|
| `launchd.daemons` | ✅ Yes (nix-darwin handles it) | `sudo launchctl kickstart -k system/com.my.service` |
| `launchd.user.agents` | ❌ No | `launchctl bootout gui/501/com.my.service && launchctl bootstrap gui/501 ~/Library/LaunchAgents/...` |

## Common Mistakes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Exit 78 "EX_CONFIG" | `$HOME` unexpanded in WorkingDirectory | Use explicit `/Users/name/...` path |
| "Operation not permitted" on kickstart | Daemon needs root for bootstrap | Use `sudo launchctl bootstrap ...` |
| Old script runs after switch | User agent plist cached | Unload + reload the plist |
| KeepAlive restart loop | `set -euo pipefail` catches error | Check stderr for the actual error |
| "Bootstrap failed: 5 Input/output error" | Need root to bootstrap GUI domain | `sudo launchctl bootstrap gui/501 ...` |
| `writeShellScriptBin` gives "Is a directory" | References the derivation dir not the binary | Use `writeShellScript` instead |

## Render Script

A launchd daemon script follows this pattern:

```nix
launchd.daemons.my-service = {
  serviceConfig = {
    Label = "com.my.service";
    UserName = primaryUser;
    ProgramArguments = ["${serviceScript}"];
    EnvironmentVariables = {
      KEY = "value";
    };
    RunAtLoad = true;
    KeepAlive = true;
    StandardOutPath = "/tmp/my-service.log";
    StandardErrorPath = "/tmp/my-service.error.log";
    WorkingDirectory = "${darwinHomeDir}/.local/share/my-service";
  };
};
```
