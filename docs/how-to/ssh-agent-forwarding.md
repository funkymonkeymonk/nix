---
title: "Use 1Password SSH Agent Forwarding"
description: "Configure SSH agent forwarding to use 1Password keys on remote machines"
type: how-to
audience: both
automation-ready: true
last-reviewed: 2026-05-04
---

# Use 1Password SSH Agent Forwarding

This guide shows you how to use your local 1Password SSH keys on remote machines (servers, MicroVMs) without copying private keys to the remote system.

## Overview

SSH agent forwarding allows you to:
- Use 1Password SSH keys on remote machines
- Authenticate git operations remotely
- Sign git commits using your local 1Password
- Never copy private keys to remote systems

## Prerequisites

- Local machine with 1Password and SSH agent enabled
- Remote machine with SSH server configured (all NixOS machines in this repo have agent forwarding enabled)

## Configure SSH Client

### Option 1: Add to SSH Config (Recommended)

Edit your local `~/.ssh/config`:

```ssh-config
# For protoman (Linux server)
Host protoman
    HostName <protoman-ip-address>
    User monkey
    ForwardAgent yes

# For MicroVMs
Host dev-vm
    HostName 192.168.83.10
    User root
    ForwardAgent yes

Host openclaw
    HostName 192.168.83.16
    User root
    ForwardAgent yes

Host matrix
    HostName 192.168.83.15
    User root
    ForwardAgent yes

# Or match all MicroVMs in the subnet
Host 192.168.83.*
    User root
    ForwardAgent yes
    StrictHostKeyChecking no
```

### Option 2: Use Command Line Flag

For one-time use:

```bash
ssh -A monkey@protoman
ssh -A root@192.168.83.16
```

## Verify Agent Forwarding

After connecting, verify the forwarded agent:

```bash
# Check that SSH_AUTH_SOCK is set
echo $SSH_AUTH_SOCK
# Should show: /tmp/ssh-XXXXXX/agent.XXXXXX

# List available keys
ssh-add -l
# Should show your 1Password keys
```

## Use Cases

### Git Operations on Remote

Once connected with agent forwarding:

```bash
# Clone/pull/push works with your local 1Password keys
git clone git@github.com:user/repo.git
git push origin main
```

You'll get biometric prompts on your **local** machine to authorize.

### Git Commit Signing

For signing commits on remote machines:

```bash
# Configure git on the remote machine
git config --global gpg.format ssh
git config --global commit.gpgsign true
git config --global user.signingkey "ssh-ed25519 AAA..."
```

When you commit, `op-ssh-sign` automatically detects the forwarded agent (via `SSH_AUTH_SOCK` and `SSH_TTY`) and uses your local 1Password for signing.

### SSH to Another Machine (Jump Host)

From a remote machine, SSH to another:

```bash
# On protoman, SSH to a MicroVM
ssh root@192.168.83.16
```

The authentication is forwarded through to your local 1Password.

## Security Considerations

- **Only use with trusted hosts** - Anyone with root access on the remote can use your forwarded agent while connected
- **Scope ForwardAgent to specific hosts** - Don't enable globally for all hosts
- **1Password is safer** than standard OpenSSH agent because it requires per-key authorization even when forwarded

## Troubleshooting

### "Could not open a connection to your authentication agent"

The remote SSH server doesn't have agent forwarding enabled. All machines using this NixOS config have it enabled by default.

### No biometric prompt appears

1. Ensure 1Password SSH agent is running locally:
   ```bash
   ssh-add -l
   ```

2. Check that `SSH_AUTH_SOCK` is set on the remote:
   ```bash
   echo $SSH_AUTH_SOCK
   ```

3. Verify you're using `-A` flag or have `ForwardAgent yes` in config

### Wrong key being used

If you have multiple keys, specify which one to use:

```ssh-config
Host protoman
    HostName <ip>
    User monkey
    ForwardAgent yes
    IdentityFile ~/.ssh/id_ed25519.pub  # Public key only!
```

## Server Configuration

All NixOS machines in this repository have SSH agent forwarding enabled:

```nix
services.openssh.settings.AllowAgentForwarding = true;
```

This includes:
- `machine-types/server.nix`
- `machine-types/server-arm.nix`
- `machine-types/desktop.nix`
- `modules/microvm/default.nix` (all MicroVMs)

> **See also:**
> - [1Password SSH Agent Forwarding docs](https://developer.1password.com/docs/ssh/agent/forwarding)
> - [Set Up 1Password SSH Signing](setup-1password.md)
