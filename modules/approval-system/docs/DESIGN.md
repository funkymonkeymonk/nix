# Phone-Based Secrets Approval System

## Overview

A secure system that allows approval of sudo commands and secret requests from your phone, leveraging 1Password for secure storage and retrieval.

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Terminal      │────▶│  Approval Agent  │────▶│   Phone App     │
│  (Requester)    │     │  (Server)        │     │  (Approver)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │                       │                        │
         │                       ▼                        │
         │              ┌──────────────────┐              │
         │              │  Notification    │              │
         │              │  Service         │              │
         │              │  (ntfy/Pushover) │              │
         │              └──────────────────┘              │
         │                       │                        │
         ▼                       ▼                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    1Password Secrets API                         │
│           (Encrypted storage & secure retrieval)                 │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Request Flow (CLI Tool: `approve-request`)

When a command needs sudo or a secret:

```bash
# Request sudo access
approve-request sudo --command "systemctl restart nginx" --duration 5m

# Request a secret from 1Password
approve-request secret --vault "Dev" --item "AWS Credentials" --field "access_key"

# Request with justification
approve-request sudo --command "apt upgrade" --reason "Security updates needed"
```

The tool:
1. Generates a unique request ID
2. Creates a secure session (temporary socket/key)
3. Sends notification to phone with request details
4. Waits for approval (with timeout)
5. Upon approval: fetches secret from 1Password and injects it
6. Logs all requests for audit

### 2. Approval Server (`approvald`)

Lightweight daemon that:
- Listens for approval requests via local socket/HTTP
- Validates requests against policy (who can request what)
- Sends push notifications via ntfy.sh or Pushover
- Receives approval/denial responses
- Communicates with 1Password CLI
- Returns credentials via secure channel

### 3. Phone Interface Options

**Option A: ntfy.sh (Recommended - Simple)**
- Self-hostable or use public instance
- Send notification with action buttons
- One-tap approve/deny
- No app installation needed

**Option B: Pushover**
- Native iOS/Android app
- Rich notifications with actions
- Priority levels

**Option C: Custom Matrix Bot**
- Message you on Matrix with approve/deny buttons
- Keeps everything in your existing chat

### 4. 1Password Integration

Uses `op` CLI with biometric unlock:
- Request arrives → 1Password prompts for biometrics (FaceID/TouchID)
- Secret retrieved → Sent to requesting terminal
- All access logged in 1Password audit log

## Security Model

### Request Authentication
- Each request signed with temporary Ed25519 key
- Request includes: command, hash, timestamp, requester identity
- Timeout: 5 minutes default (configurable)

### Approval Authorization
- Phone approver must be registered device
- Approval requires biometric unlock (1Password)
- Optional: 2FA code from phone
- All approvals logged

### Secret Handling
- Secrets never written to disk unencrypted
- In-memory only, cleared after use
- Ephemeral session keys
- No shell history capture

### Audit Trail
- All requests logged: who, what, when, result
- Tamper-resistant logging (signed entries)
- Optional: webhook to audit system

## Implementation Plan

### Phase 1: Core CLI
- `approve-request` command
- Local socket communication
- Basic notification (ntfy)

### Phase 2: Policy Engine
- Configurable approval rules
- User/role-based access
- Command allowlisting

### Phase 3: Advanced Features
- Time-based auto-approval (maintenance windows)
- Request queuing
- Batch approvals
- Slack/Discord integrations

## Configuration

```nix
# modules/approval-system/default.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.approval-system;
in {
  options.services.approval-system = {
    enable = mkEnableOption "approval system for sudo and secrets";
    
    notification = {
      type = mkOption {
        type = types.enum [ "ntfy" "pushover" "matrix" ];
        default = "ntfy";
      };
      ntfy = {
        server = mkOption { type = types.str; };
        topic = mkOption { type = types.str; };
      };
      pushover = {
        userKey = mkOption { type = types.str; };
        appToken = mkOption { type = types.str; };
      };
    };
    
    onepassword = {
      account = mkOption { type = types.str; };
      vault = mkOption { type = types.str; default = "Approval Secrets"; };
    };
    
    policy = {
      autoApprove = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Commands that auto-approve without phone";
      };
      requireJustification = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };
  
  config = mkIf cfg.enable {
    # Implementation here
  };
}
```

## Usage Examples

### Daily Use

```bash
# Terminal shows:
$ systemctl restart nginx
🔐 Approval required for: systemctl restart nginx
📱 Sent to phone... [waiting]
✅ Approved by phone at 12:34:56
[sudo] password for monkey: (auto-filled)
✓ Service restarted

# Or with explicit request:
$ approve-run -- sudo apt upgrade
```

### Scripts/Automation

```bash
#!/usr/bin/env bash
# Auto-approve during maintenance window
if is_maintenance_window; then
  APPROVAL_AUTO=1 systemctl restart service
else
  systemctl restart service  # Requires approval
fi
```

## NixOS Integration

The module will:
1. Install `op` (1Password CLI) and configure it
2. Create systemd service for `approvald`
3. Set up sudo wrapper that checks policy first
4. Configure ntfy/pushover credentials securely
5. Add shell integration (zsh/fish aliases)

## Phone Experience

**Notification arrives:**
```
🔐 Approval Request
─────────────────────────
Request: sudo systemctl restart nginx
From: drlight (monkey)
Time: 2026-03-01 13:45
Reason: Web server updates

[  ✅ Approve  ]  [  ❌ Deny  ]
```

**Tap Approve → 1Password unlock prompt → Biometric → Done**

## Next Steps

1. ✅ Design document (this file)
2. Implement core CLI tool
3. Implement approval daemon
4. Create NixOS module
5. Add tests
6. Document setup
