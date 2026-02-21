# How to Set Up SSH Commit Signing

This guide shows you how to configure SSH-based git commit signing using 1Password.

## Prerequisites

- 1Password installed with CLI (`op` command available)
- SSH key stored in 1Password

## Steps

### 1. Enable 1Password SSH Agent

In 1Password app:
1. Go to **Settings** > **Developer**
2. Enable **SSH Agent**

### 2. Store Your SSH Key

Add your SSH private key to 1Password:
1. Create a new SSH Key item
2. Or import an existing key

### 3. Register Your Public Key

Add your SSH public key to your Git hosting service:

**GitHub:**
1. Go to **Settings** > **SSH and GPG keys**
2. Click **New SSH key**
3. Select **Signing key** as the key type
4. Paste your public key

**GitLab/Bitbucket:** Similar process in their SSH key settings.

### 4. Apply Configuration

Rebuild your system to apply the git signing configuration:

```bash
devenv tasks run switch
```

The following git configuration is applied automatically on macOS:
```bash
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global gpg.ssh.program "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
```

### 5. Test Signing

Create a test commit:

```bash
git commit --allow-empty -m "test signing"
```

You should see a biometric prompt from 1Password.

Verify the signature:

```bash
git log --show-signature -1
```

## Verification

After setup:
- GitHub/GitLab/Bitbucket will show commits as "Verified"
- `git log --show-signature` shows local verification
- Biometric prompt appears for each signed commit

## Troubleshooting

**No biometric prompt:**
- Ensure 1Password SSH agent is enabled
- Restart your terminal

**Signature verification fails:**
- Verify public key is registered as a "Signing key" (not just SSH key)
- Check that the key in 1Password matches the registered key
