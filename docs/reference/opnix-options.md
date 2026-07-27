---
title: "opnix Configuration Options"
description: "Complete reference for opnix configuration options in the Nix system configuration"
type: reference
audience: user
last-reviewed: 2026-04-08
---

# opnix Configuration Options

Reference documentation for configuring opnix (1Password secrets integration) in your NixOS system.

## Overview

opnix enables secure secrets management by fetching credentials from 1Password and making them available on your NixOS machines at runtime.

## Options

### `myConfig.onepassword.enable`

Whether to enable 1Password integration.

| Property | Value |
|----------|-------|
| Type | `boolean` |
| Default | `true` |
| Description | Enables the 1Password CLI (`op`) on all systems, and opnix services on NixOS when available |

**Example:**

```nix
myConfig.onepassword.enable = true;
```

---

### `myConfig.onepassword.tokenFile`

Path to the 1Password service account token file.

| Property | Value |
|----------|-------|
| Type | `path` |
| Default | `/etc/opnix-token` |
| Description | Location of the 1Password service account token used by opnix to authenticate |

**Example:**

```nix
myConfig.onepassword.tokenFile = /etc/my-custom/opnix-token;
```

**Security Requirements:**
- File must exist before `opnix-secrets` service starts
- Must have permissions `0600` (readable only by owner)
- Should be owned by root
- Never commit this file to version control

---

### `myConfig.onepassword.secrets`

Attribute set of secrets to fetch from 1Password.

| Property | Value |
|----------|-------|
| Type | `attrsOf secret` |
| Default | `{}` (empty) |
| Description | Secrets configuration - each entry defines a secret to fetch and where to place it |

**Example:**

```nix
myConfig.onepassword.secrets = {
  apiKey = {
    reference = "op://Private/MyAPI/credential";
    path = "/run/secrets/api-key";
    mode = "0600";
    owner = "myapp";
    services = ["myapp-service"];
  };
};
```

---

## Secret Configuration

Each secret in `myConfig.onepassword.secrets` is an attribute set with the following options:

### `reference`

1Password reference path to the secret.

| Property | Value |
|----------|-------|
| Type | `string` |
| Required | Yes |
| Format | `op://vault/item/field` |

**Examples:**

```nix
reference = "op://Private/Database/password";
reference = "op://Homelab/WiFi/password";
reference = "op://Work/AWS Access Key/access-key-id";
```

**Reference Format:**
- `vault` - The 1Password vault name (URL-encoded if contains spaces)
- `item` - The item name within the vault
- `field` - The specific field to retrieve (e.g., `password`, `credential`, `username`)

---

### `path`

Filesystem path where the secret will be written.

| Property | Value |
|----------|-------|
| Type | `string` |
| Required | Yes |
| Default | None |

**Recommendations:**
- Use `/run/secrets/` for runtime secrets (tmpfs, cleared on reboot)
- Use `/var/lib/secrets/` for persistent secrets
- Avoid `/tmp/` as it may be world-readable

**Example:**

```nix
path = "/run/secrets/database-password";
```

---

### `mode`

File permissions for the secret.

| Property | Value |
|----------|-------|
| Type | `string` |
| Required | No |
| Default | `"0600"` |
| Format | Octal permissions (e.g., `"0600"`, `"0444"`, `"0400"`) |

**Common Values:**

| Mode | Description | Use Case |
|------|-------------|----------|
| `0600` | Owner read/write | Private keys, API tokens |
| `0400` | Owner read-only | Certificates, public keys |
| `0444` | All read | TLS certificates that services need to read |
| `0640` | Owner read/write, group read | Shared secrets within a group |

**Example:**

```nix
mode = "0400";  # Read-only for owner
```

---

### `owner`

User that owns the secret file.

| Property | Value |
|----------|-------|
| Type | `string` |
| Required | No |
| Default | `"root"` |

**Example:**

```nix
owner = "postgres";  # PostgreSQL can read its password
```

---

### `group`

Group that owns the secret file.

| Property | Value |
|----------|-------|
| Type | `string` |
| Required | No |
| Default | `"root"` |

**Example:**

```nix
group = "www-data";  # Web server group can access
```

---

### `services`

List of systemd services to restart when this secret changes.

| Property | Value |
|----------|-------|
| Type | `listOf string` |
| Required | No |
| Default | `[]` (empty) |
| Description | Service names that depend on this secret |

**Example:**

```nix
services = ["postgresql" "myapp-api"];
```

When the secret value changes in 1Password, these services will be automatically restarted to pick up the new value.

---

## Other 1Password Options

### `myConfig.onepassword.enableGUI`

Enable 1Password GUI application (Darwin only).

| Property | Value |
|----------|-------|
| Type | `boolean` |
| Default | `true` |
| Platform | Darwin (macOS) only |

---

### `myConfig.onepassword.enableSSHAgent`

Enable 1Password SSH agent integration.

| Property | Value |
|----------|-------|
| Type | `boolean` |
| Default | `true` |

---

### `myConfig.onepassword.enableGitSigning`

Enable git commit signing with 1Password SSH keys.

| Property | Value |
|----------|-------|
| Type | `boolean` |
| Default | `true` |

---

### `myConfig.onepassword.signingKey`

SSH key name in 1Password for git signing.

| Property | Value |
|----------|-------|
| Type | `string` |
| Default | `""` |
| Example | `"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."` |

---

### `myConfig.onepassword.enableSudo`

Enable 1Password for sudo authentication (NixOS only).

| Property | Value |
|----------|-------|
| Type | `boolean` |
| Default | `true` |
| Platform | NixOS only |

---

## Systemd Services

When opnix is enabled, the following systemd services are managed:

### `opnix-secrets.service`

Fetches secrets from 1Password and writes them to the configured paths.

| Property | Value |
|----------|-------|
| Type | `oneshot` |
| Trigger | Boot, and when secrets configuration changes |
| Dependencies | Network must be available |

**Checking status:**

```bash
sudo systemctl status opnix-secrets
sudo journalctl -u opnix-secrets
```

---

## Complete Configuration Example

```nix
{
  myConfig.onepassword = {
    enable = true;
    tokenFile = /etc/opnix-token;
    
    secrets = {
      # Database password for PostgreSQL
      dbPassword = {
        reference = "op://Private/Production DB/password";
        path = "/run/secrets/db-password";
        mode = "0400";
        owner = "postgres";
        services = ["postgresql"];
      };
      
      # API key for a custom application
      apiKey = {
        reference = "op://Work/MyService/api-key";
        path = "/run/secrets/myapp-api-key";
        mode = "0600";
        owner = "myapp";
        group = "myapp";
        services = ["myapp-api" "myapp-worker"];
      };
      
      # TLS certificate (readable by services)
      tlsCert = {
        reference = "op://Homelab/Website/cert";
        path = "/run/secrets/tls.crt";
        mode = "0444";
      };
      
      # TLS private key (restricted)
      tlsKey = {
        reference = "op://Homelab/Website/private-key";
        path = "/run/secrets/tls.key";
        mode = "0400";
        owner = "nginx";
        services = ["nginx"];
      };
    };
  };
  
  # Example service using the secret
  services.postgresql = {
    enable = true;
    initialScript = ''
      ALTER USER postgres WITH PASSWORD '$(cat /run/secrets/db-password)';
    '';
  };
}
```

---

## See Also

- [Set up 1Password service account](../how-to/setup-opnix-service-account.md) - How-to guide
- [Getting started with opnix](../tutorials/getting-started-opnix.md) - Tutorial
- [opnix security architecture](../explanation/opnix-security.md) - Explanation
