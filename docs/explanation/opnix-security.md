---
title: "opnix Security Architecture"
description: "Understanding how opnix keeps your secrets secure on NixOS machines"
type: explanation
audience: user
last-reviewed: 2026-04-08
---

# opnix Security Architecture

This document explains the security model behind opnix, how it protects your secrets, and the design decisions that make it secure by default.

## Design Principles

opnix follows these core security principles:

1. **No secrets in the repository** - Configuration references secrets by path, not value
2. **Runtime retrieval only** - Secrets are fetched at runtime, not build time
3. **Minimal privilege** - Each machine gets only the secrets it needs via service accounts
4. **Fail-secure** - If authentication fails, no secrets are exposed
5. **Ephemeral storage** - Secrets live in RAM (tmpfs), not on disk

## How It Works

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Your NixOS Machine                        │
│                                                              │
│  ┌──────────────────┐      ┌──────────────────────┐         │
│  │   1Password      │      │   opnix Service      │         │
│  │   (Cloud)        │◄────►│   (onepassword-      │         │
│  │                  │      │    secrets.service)  │         │
│  └──────────────────┘      └──────────┬───────────┘         │
│           ▲                           │                     │
│           │  Service Account Token    │                     │
│           │  (ops_...)                │                     │
│           │                           ▼                     │
│  ┌──────────────────┐      ┌──────────────────────┐         │
│  │ /etc/opnix-token │      │   /run/secrets/      │         │
│  │ (root:root 600)  │      │   (tmpfs, RAM only)  │         │
│  └──────────────────┘      └──────────────────────┘         │
│                                       │                     │
│                                       ▼                     │
│                              ┌──────────────────────┐       │
│                              │  Your Services       │       │
│                              │  (PostgreSQL,        │       │
│                              │   Nginx, etc.)       │       │
│                              └──────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### The Secret Lifecycle

#### 1. Authentication

At boot, the `opnix-secrets` service starts and reads the service account token from `/etc/opnix-token`.

**Security features:**
- Token file must have permissions `0600` (owner read/write only)
- Token is never logged or displayed
- Service runs as root to read the token, then drops privileges

#### 2. Retrieval

The service connects to 1Password's API using the token and fetches only the secrets you've configured.

**Security features:**
- Encrypted TLS connection to 1Password
- Service account has limited scope (only specific vaults)
- No interactive authentication required
- Token can be revoked instantly from 1Password web interface

#### 3. Storage

Secrets are written to `/run/secrets/` which is a tmpfs mount (RAM-only storage).

**Security features:**
- **Never touches disk** - Secrets exist only in RAM
- **Cleared on reboot** - No persistent storage of secrets
- **Permission enforcement** - Each secret has specific owner/mode
- **No swap** - Secrets won't be written to swap space

#### 4. Usage

Services read secrets from `/run/secrets/` at runtime.

**Security features:**
- Services only get the secrets they need
- File permissions control access
- Secrets can be injected via environment files or read directly
- Services are restarted when secrets change

## Security Model Details

### Service Accounts vs. Personal Access

**Why service accounts?**

| Aspect | Personal Account | Service Account |
|--------|------------------|-----------------|
| Authentication | Master password + 2FA | Token only |
| Scope | All vaults you can access | Specific vaults only |
| Revocation | Change master password | Disable token instantly |
| Audit Trail | User activity logs | Service-specific logs |
| Risk | If compromised, all vaults at risk | Limited blast radius |

Service accounts follow the principle of least privilege - each machine gets access only to the vaults it needs.

### Token Security

The service account token is the key to your secrets. Here's how it's protected:

**File System Security:**
- Stored at `/etc/opnix-token` with `0600` permissions
- Owned by root:root
- Never included in Nix store or configuration
- Must be manually placed on each machine

**Operational Security:**
- Tokens can be rotated regularly
- Old tokens can be revoked without affecting new ones
- 1Password logs all token usage
- Tokens have no interactive access (can't unlock GUI)

**Comparison to alternatives:**

| Approach | Security Level | Management |
|----------|---------------|------------|
| Hardcoded secrets in config | ❌ Poor | Easy |
| Environment variables | ⚠️ Fair | Medium |
| Files in Nix store | ⚠️ Fair | Easy |
| **opnix with service accounts** | ✅ Good | Medium |
| Hardware security modules | ✅ Excellent | Hard |

### Runtime vs. Build Time

**Why fetch secrets at runtime instead of build time?**

**Build-time secrets (traditional approach):**
```nix
# ❌ Secret embedded in Nix store
environment.systemPackages = [ 
  (pkgs.writeShellScriptBin "myapp" ''
    API_KEY="actual-secret-here"  # Visible in Nix store!
    exec myapp "$@"
  '')
];
```

Problems:
- Secret visible in Nix store (world-readable)
- Secret stored in binary cache
- Anyone with build access sees the secret

**Runtime secrets (opnix approach):**
```nix
# ✅ Secret fetched at runtime
systemd.services.myapp = {
  serviceConfig.EnvironmentFile = "/run/secrets/api-key";
};
```

Benefits:
- Secret never in Nix store
- Not stored in binary cache
- Only runtime access to the machine can read secrets
- Secrets can be rotated without rebuilding

## Threat Model

### What opnix Protects Against

✅ **Insiders with build access** - Can't see secrets in configuration  
✅ **Binary cache compromise** - Secrets not in cache  
✅ **Repository leaks** - Only references, not values  
✅ **Old hardware disposal** - Secrets in RAM, not disk  
✅ **Accidental logging** - Secrets not in build logs  

### What Requires Additional Protection

⚠️ **Root access on the machine** - Can read all secrets  
⚠️ **Token file compromise** - Attacker can fetch secrets  
⚠️ **Network interception** - Requires TLS compromise  
⚠️ **1Password account compromise** - All secrets at risk  

### Mitigations

| Threat | Mitigation |
|--------|------------|
| Root access | Use minimal secrets, rotate tokens regularly |
| Token compromise | Short-lived tokens, audit logging, quick revocation |
| Network attack | TLS 1.3, certificate pinning, mutual TLS where possible |
| 1Password compromise | Regular backups, incident response plan |

## Best Practices

### Service Account Hygiene

1. **Create per-machine accounts** - Don't reuse tokens across machines
2. **Limit vault access** - Only grant access to necessary vaults
3. **Rotate tokens regularly** - Set calendar reminders
4. **Monitor access logs** - Check 1Password for unusual activity
5. **Revoke immediately on compromise** - Don't wait

### Token File Security

1. **Use Ansible/Terraform** - Automate token placement securely
2. **Never commit tokens** - Add `/etc/opnix-token` to `.gitignore`
3. **Use temporary tokens for testing** - Revoke after use
4. **Secure backups** - Encrypt backups containing token files

### Secret Usage Patterns

**Good:**
```nix
# Service reads secret from file
systemd.services.myapp = {
  serviceConfig.LoadCredential = "api-key:/run/secrets/api-key";
};
```

**Avoid:**
```nix
# Secret in command line (visible in process list)
script = ''
  myapp --api-key=$(cat /run/secrets/api-key)
'';
```

## Comparison to Alternatives

### vs. sops-nix

| Feature | opnix | sops-nix |
|---------|-------|----------|
| Secrets stored in | 1Password cloud | Git repository (encrypted) |
| Rotation | Automatic from 1Password | Manual re-encryption |
| Team sharing | Via 1Password sharing | Via GPG keys |
| Offline access | ❌ No | ✅ Yes |
| Audit trail | ✅ 1Password logs | ❌ Limited |
| Cost | 1Password subscription | Free |

### vs. agenix

| Feature | opnix | agenix |
|---------|-------|--------|
| Encryption | 1Password handles it | Age encryption |
| Key management | 1Password service | SSH host keys |
| Rotation | Automatic | Manual |
| Complexity | Lower | Higher |
| Vendor lock-in | 1Password | None |

## When to Use opnix

**opnix is ideal when:**
- You already use 1Password
- You need centralized secret management
- You want automatic secret rotation
- You value audit logging
- You have internet connectivity

**Consider alternatives when:**
- You need offline operation
- You don't use 1Password
- You want zero vendor dependencies
- You have strict air-gapped requirements

## See Also

- [Set up 1Password service account](../how-to/setup-opnix-service-account.md)
- [Getting started with opnix](../tutorials/getting-started-opnix.md)
- [opnix configuration reference](../reference/opnix-options.md)
- [1Password Service Accounts documentation](https://developer.1password.com/docs/service-accounts/)
- [sops-nix documentation](https://github.com/Mic92/sops-nix)
