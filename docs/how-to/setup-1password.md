# Set Up 1Password SSH Signing

This guide shows you how to configure SSH-based git commit signing using 1Password.

## Prerequisites

- 1Password desktop app installed
- An SSH key stored in 1Password

## Step 1: Enable 1Password SSH Agent

1. Open 1Password
2. Go to **Settings** → **Developer**
3. Enable **SSH Agent**
4. Enable **Use the SSH agent**

## Step 2: Add Your SSH Key to 1Password

If you don't have an SSH key in 1Password:

1. In 1Password, click **+ New Item** → **SSH Key**
2. Either generate a new key or import an existing one
3. Name it something recognizable (e.g., "GitHub Signing Key")

## Step 3: Register Key with GitHub/GitLab

1. Copy your **public key** from 1Password
2. Go to GitHub → **Settings** → **SSH and GPG keys**
3. Click **New SSH key**
4. Set **Key type** to **Signing Key**
5. Paste your public key and save

## Step 4: Configure This Repository

The configuration is automatic when `onepassword.enable = true` in your machine config. The following settings are applied:

```nix
# Applied automatically by modules/common/users.nix
programs.git.settings = {
  gpg.format = "ssh";
  commit.gpgsign = true;
  gpg.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
};
```

## Step 5: Test Signing

Make a test commit:

```bash
git commit --allow-empty -m "test: verify commit signing"
```

You should see a 1Password biometric prompt (Touch ID/Face ID).

Verify the signature:

```bash
git log --show-signature -1
```

## Troubleshooting

### "gpg.ssh.program not found"

Ensure 1Password is installed at `/Applications/1Password.app`.

### No biometric prompt appears

1. Check 1Password SSH agent is enabled
2. Restart 1Password
3. Run `ssh-add -l` to verify the agent is working

### Commits show as "Unverified" on GitHub

1. Ensure you added the key as a **Signing Key** (not just Authentication)
2. Verify the email in your git config matches your GitHub account

> **See also:** [1Password SSH documentation](https://developer.1password.com/docs/ssh/)
