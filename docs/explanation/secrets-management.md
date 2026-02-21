# Secrets Management

This document explains how secrets are managed in this configuration.

## Problem Statement

Nix configurations are stored in git and the Nix store, both of which are readable. Secrets (API keys, passwords, private keys) cannot be stored there safely.

## Approach: Runtime Access via 1Password

Instead of storing secrets in the configuration, this system accesses them at runtime through 1Password CLI.

### How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Application    │────▶│  1Password CLI  │────▶│  1Password      │
│  (git, ssh)     │     │  (op)           │     │  Vault          │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                │
                                ▼
                        Biometric Auth
                        (Touch ID/Face ID)
```

1. Application requests credential (e.g., git needs SSH key)
2. 1Password CLI intercepts or provides the credential
3. User authenticates via biometrics
4. Credential is provided temporarily

### SSH Agent Integration

1Password's SSH agent manages SSH keys:
- Private keys never leave 1Password
- Keys are available to SSH clients transparently
- Biometric authentication for each use

### Git Signing

SSH keys in 1Password can sign git commits:
- `op-ssh-sign` program provides signing
- Same key for authentication and signing
- Verified commits without GPG complexity

## Why Not Alternatives?

### agenix/sops-nix

These tools encrypt secrets that are decrypted at build or activation time.

**Pros**: Secrets in repo, works offline
**Cons**: Key management complexity, secrets in Nix store during build

For this use case, 1Password provides:
- Better UX (biometric auth)
- No key distribution problem
- Secrets never on disk

### Environment Variables

Secrets in environment files (`.env`).

**Pros**: Simple, works anywhere
**Cons**: Files on disk, easy to commit accidentally

### Hashicorp Vault

Enterprise secret management.

**Pros**: Audit trails, dynamic secrets
**Cons**: Requires infrastructure, complexity

## Security Properties

### What's Protected

- **Private keys**: Never stored on disk
- **API tokens**: Accessed at runtime only
- **Passwords**: Retrieved when needed

### What's Not Protected

- **Configuration structure**: Visible in git
- **Public keys**: Stored in configuration
- **Service names**: What you're connecting to

## Trade-offs

### Online Requirement

1Password requires internet for initial unlock. After unlock:
- SSH agent works offline for session duration
- Some operations may require re-auth

### Vendor Lock-in

This approach depends on 1Password. Migration requires:
- Exporting keys from 1Password
- Setting up alternative secret management
- Updating configuration references

### Biometric Fatigue

Frequent operations trigger repeated biometric prompts. Mitigation:
- 1Password caches auth for session
- Batch operations when possible

## Implementation Details

### SSH Agent

```nix
# Enabled in modules/common/onepassword.nix
programs._1password.enable = true;
programs._1password-gui.enable = true;
```

### Git Signing (macOS)

```nix
programs.git.extraConfig = {
  gpg.format = "ssh";
  commit.gpgsign = true;
  gpg.ssh.program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
};
```

## Best Practices

1. **Store all secrets in 1Password**: Don't split between managers
2. **Use SSH keys for signing**: Simpler than GPG
3. **Enable biometric auth**: Balance security and convenience
4. **Audit vault regularly**: Remove unused credentials
