---
title: "Set Up 1Password Service Account for opnix"
description: "Configure a 1Password service account to enable secure secrets management with opnix on NixOS machines"
type: how-to
audience: user
last-reviewed: 2026-04-08
---

# Set Up 1Password Service Account for opnix

This guide shows you how to configure a 1Password service account and enable opnix secrets management on your NixOS machines.

## Prerequisites

- A 1Password account (individual, family, or business)
- Administrative access to a NixOS machine
- Basic familiarity with the command line

## Create a 1Password Service Account

Service accounts provide programmatic access to 1Password vaults without requiring interactive authentication.

1. **Navigate to Service Accounts**
   
   Go to [https://my.1password.com/developer-tools/service-accounts](https://my.1password.com/developer-tools/service-accounts)

2. **Create New Service Account**
   
   Click **"Create Service Account"** and give it a descriptive name:
   - For a server: `type-server` or `zero`
   - For a VM: `openclaw-vm` or `matrix-vm`
   - For general use: `nixos-secrets`

3. **Select Vaults**
   
   Choose which vaults the service account can access:
   - **Private** - Your personal vault
   - **Homelab** - Infrastructure secrets
   - **Work** - Work-related credentials
   
   > **Security Tip:** Only grant access to vaults that contain secrets needed by this specific machine. Follow the principle of least privilege.

4. **Copy the Token**
   
   After creation, copy the service account token. It starts with `ops_` followed by a long string.
   
   > ⚠️ **Important:** This token is shown only once. Save it securely now.

## Place the Token on Your NixOS Machine

The token must be placed at `/etc/opnix-token` with restricted permissions.

### Step-by-Step

1. **Create the token file with secure permissions (atomic):**

   ```bash
   sudo install -m 600 /dev/null /etc/opnix-token
   ```

   Using `install` creates the file with the correct permissions in a single atomic operation, avoiding the race window that `touch` + `chmod` would leave.

2. **Add your token:**

   ```bash
   sudo nano /etc/opnix-token
   ```

   Paste your service account token (the `ops_...` string), then save and exit.

3. **Verify permissions:**

   ```bash
   ls -la /etc/opnix-token
   ```

   You should see:
   ```
   -rw------- 1 root root  71 Apr  8 10:00 /etc/opnix-token
   ```

## Verify opnix is Working

After placing the token, rebuild your NixOS configuration:

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

Check that the service is running:

```bash
sudo systemctl status opnix-secrets
```

Test that `op` can access your vaults:

```bash
op vault list
```

You should see a list of vaults that your service account has access to.

## Configure Secrets (Optional)

Once the service account is working, you can configure specific secrets in your NixOS configuration:

```nix
myConfig.onepassword.secrets = {
  myApiKey = {
    reference = "op://Private/MyAPI/credential";
    path = "/run/secrets/my-api-key";
    mode = "0600";
    owner = "myuser";
    services = ["my-service"];  # Restart when secret changes
  };
};
```

## Troubleshooting

### Service fails to start

```bash
sudo journalctl -u opnix-secrets
```

Common causes:
- Token file doesn't exist at `/etc/opnix-token`
- Token file has wrong permissions (must be 600)
- Token is invalid or expired
- Service account doesn't have access to referenced vaults

### "Token file not found" error

Ensure the file exists:
```bash
test -f /etc/opnix-token && echo "Token exists" || echo "Token missing"
```

### Permission denied

Fix permissions:
```bash
sudo chmod 600 /etc/opnix-token
sudo chown root:root /etc/opnix-token
```

## Next Steps

- Learn about [opnix security architecture](../explanation/opnix-security.md)
- See all available [configuration options](../reference/opnix-options.md)
- Follow the [getting started tutorial](../tutorials/getting-started-opnix.md)

## See Also

- [1Password Service Accounts documentation](https://developer.1password.com/docs/service-accounts/get-started/)
- [opnix GitHub repository](https://github.com/brizzbuzz/opnix)
