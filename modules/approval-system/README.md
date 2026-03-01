# Approval System - Phone-Based Sudo & Secrets Authorization

A secure approval system for NixOS that lets you approve sudo commands and 1Password secrets from your phone.

## Quick Start

### 1. Setup ntfy.sh (Recommended)

**Option A: Use public ntfy.sh (easiest)**
1. Download ntfy app: https://ntfy.sh/
2. Subscribe to a unique topic (e.g., `approval-yourname-drlight`)
3. No account needed!

**Option B: Self-host ntfy** (more private)
```nix
# In your nix config
services.ntfy-sh.enable = true;
services.ntfy-sh.settings.base-url = "https://ntfy.yourdomain.com";
```

### 2. Enable in NixOS

```nix
# In your system configuration
{ config, pkgs, ... }: {
  imports = [
    ./modules/approval-system
  ];
  
  services.approval-system = {
    enable = true;
    user = "monkey";
    
    notification = {
      type = "ntfy";
      ntfy = {
        server = "https://ntfy.sh";
        topic = "approval-monkey-drlight";
      };
    };
    
    onepassword = {
      enable = true;
      account = "your-account.1password.com";
    };
    
    policy = {
      # Safe commands that don't need approval
      autoApprove = [ "uptime" "whoami" "ls" ];
      timeout = 300;  # 5 minutes
    };
  };
}
```

### 3. Use It

```bash
# Request sudo approval
approve-request sudo --command "systemctl restart nginx"
# → Notification sent to phone
# → Tap "Approve" on phone
# → Command executes automatically

# Request secret from 1Password  
approve-request secret --vault Dev --item "API Key"
# → Biometric unlock on phone
# → Secret returned to terminal

# Quick aliases
as systemctl restart nginx  # approve-sudo
gs Dev "API Key" token      # get-secret
```

## How It Works

```
┌─────────────┐    approve-request     ┌──────────────┐
│  Terminal   │ ──────────────────────▶ │  approvald   │
│  (drlight)  │                         │  (daemon)    │
└─────────────┘                         └──────────────┘
                                              │
                                              │ ntfy notification
                                              ▼
                                        ┌──────────────┐
                                        │    Phone     │
                                        │  (ntfy app)  │
                                        └──────────────┘
                                              │
                                              │ Tap Approve
                                              ▼
                                        ┌──────────────┐
                                        │ 1Password    │
                                        │ Biometric    │
                                        └──────────────┘
                                              │
                                              │ Return secret
                                              ▼
                                        ┌──────────────┐
                                        │   Terminal   │
                                        │  (continues) │
                                        └──────────────┘
```

## Files

- `bin/approve-request` - CLI tool for requesting approvals
- `bin/approvald` - Daemon that handles requests and notifications
- `default.nix` - NixOS module with full configuration
- `docs/DESIGN.md` - Complete architecture documentation
- `docs/config.example.toml` - Example configuration

## Security

- ✅ Each request has unique ID and session key
- ✅ Secrets never written to disk (memory only)
- ✅ 1Password biometric required for every secret
- ✅ Audit log of all requests
- ✅ Auto-approve only for safe commands
- ✅ Timeout prevents indefinite waiting

## Next Steps

1. **Install ntfy app** on your phone
2. **Enable the NixOS module** in your config
3. **Run `approvald start`** to start the daemon
4. **Test**: `approve-request sudo --command whoami`
5. **See notification on phone** → Approve → Done!

## Advanced: Custom Notification

Want to use Matrix, Discord, or Pushover instead?

Just change `services.approval-system.notification.type` and configure the appropriate credentials.

See `docs/DESIGN.md` for all options.
