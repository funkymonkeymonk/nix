---
title: "Getting Started with opnix"
description: "Learn how to securely manage secrets on your NixOS machines using 1Password and opnix"
type: tutorial
audience: user
last-reviewed: 2026-04-08
---

# Getting Started with opnix

In this tutorial, you'll learn how to use opnix to securely manage secrets on your NixOS machines. By the end, you'll have:

- A working 1Password service account
- The opnix service running on your NixOS machine
- A secret from 1Password automatically available on your system
- Understanding of how to add more secrets

## What You'll Need

- A 1Password account
- A NixOS machine (physical, VM, or MicroVM)
- About 15 minutes

> **Note:** This tutorial uses a test API key as an example. You can follow along with any secret you have in 1Password.

## Step 1: Create a Test Secret in 1Password

First, let's create a secret to work with.

1. Open 1Password
2. Create a new item in your Private vault
3. Choose "API Credential" as the type
4. Fill in:
   - **Name:** Demo API Key
   - **Credential:** `test-api-key-12345`
   - **Username:** demo-user
5. Save the item

Note the item's location: `op://Private/Demo API Key/credential`

## Step 2: Create a Service Account

Service accounts let machines access 1Password without your master password.

1. Go to [https://my.1password.com/developer-tools/service-accounts](https://my.1password.com/developer-tools/service-accounts)
2. Click **Create Service Account**
3. Name it: `nixos-tutorial`
4. Grant access to your **Private** vault
5. Copy the token (starts with `ops_`)

> ⚠️ The token is shown only once. Keep it safe!

## Step 3: Place the Token on Your Machine

SSH into your NixOS machine and create the token file:

```bash
# Create the file with secure permissions
sudo mkdir -p /etc
sudo install -m 600 /dev/null /etc/opnix-token

# Add your token
sudo nano /etc/opnix-token
# Paste the ops_... token, then save (Ctrl+O, Enter, Ctrl+X)
```

Verify it's set up correctly:

```bash
ls -la /etc/opnix-token
# Should show: -rw------- 1 root root
```

## Step 4: Configure Your First Secret

Edit your machine's configuration file. If you're using flakes, this is typically in your flake repository.

Add the secret configuration:

```nix
{
  myConfig.onepassword.secrets = {
    demoApiKey = {
      reference = "op://Private/Demo API Key/credential";
      path = "/run/secrets/demo-api-key";
      mode = "0600";
      owner = "your-username";
    };
  };
}
```

Replace `your-username` with your actual username.

## Step 5: Rebuild and Verify

Apply the configuration:

```bash
sudo nixos-rebuild switch --flake .#your-hostname
```

Check that the secret was fetched:

```bash
# Check the service status
sudo systemctl status opnix-secrets

# View the secret (as root)
sudo cat /run/secrets/demo-api-key
# Output: test-api-key-12345

# Or view as your user (if you set the owner)
cat /run/secrets/demo-api-key
test-api-key-12345
```

## Step 6: Use the Secret in a Service

Now let's use this secret in an actual service. We'll create a simple service that reads the API key from the secret file.

```nix
{
  systemd.services.demo-api-consumer = {
    description = "Demo service that uses API key";

    serviceConfig = {
      Type = "oneshot";
      User = "your-username";
    };

    script = ''
      API_KEY=$(cat /run/secrets/demo-api-key)
      echo "Using API key: $API_KEY"
    '';
  };
}
```

> **Note:** `EnvironmentFile` in systemd expects `KEY=value` format. Since opnix writes the raw secret value, read it directly with `cat` or use `LoadCredential` for systemd credential injection.

After rebuilding, test it:

```bash
sudo systemctl start demo-api-consumer
sudo journalctl -u demo-api-consumer
```

You'll see the API key being used by the service.

## Understanding What Happened

Let's break down what opnix did:

1. **At boot**: The `opnix-secrets` service starts
2. **Authentication**: It reads the token from `/etc/opnix-token`
3. **Fetching**: It contacts 1Password and retrieves your secrets
4. **Storage**: Secrets are written to the configured path (or `/var/lib/opnix/secrets/<name>` by default)
5. **Permissions**: Files are created with the ownership and permissions you specified
6. **Services**: Any services that depend on the secrets are started after secrets are ready

## Next Steps

Congratulations! You now have opnix working. Here's what to explore next:

### Add More Secrets

Simply add more entries to `myConfig.onepassword.secrets`:

```nix
myConfig.onepassword.secrets = {
  demoApiKey = { /* ... */ };
  databasePassword = {
    reference = "op://Private/Production DB/password";
    path = "/run/secrets/db-password";
    mode = "0400";
    owner = "postgres";
  };
  tlsCertificate = {
    reference = "op://Homelab/Website TLS/certificate";
    path = "/run/secrets/tls.crt";
    mode = "0444";
  };
};
```

### Use Secrets in Applications

Most services can read secrets from files:

```nix
services.postgresql = {
  enable = true;
  initialScript = pkgs.writeText "init.sql" ''
    ALTER USER postgres WITH PASSWORD '$(cat /run/secrets/db-password)';
  '';
};
```

### Learn More

- [Set up a 1Password service account](../how-to/setup-opnix-service-account.md) - Production setup guide
- [opnix configuration reference](../reference/opnix-options.md) - All available options
- [opnix security architecture](../explanation/opnix-security.md) - How it keeps secrets safe

## Common Issues

**Service account can't access vault**

Make sure the service account has access to the vault containing your secrets. You can check this in the 1Password web interface.

**Permission denied when reading secret**

Ensure the `owner` and `mode` in your secret configuration match what the service expects.

**Changes not applying**

Remember to run `sudo nixos-rebuild switch` after changing your configuration.
