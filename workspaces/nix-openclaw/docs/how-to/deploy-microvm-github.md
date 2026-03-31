# Deploy a MicroVM from GitHub Main

This guide shows you how to deploy any MicroVM on a NixOS host using the configuration from the GitHub main branch.

## Prerequisites

- [MicroVM host set up](setup-microvm-host.md)
- 1Password service account token placed at `/etc/opnix/token`
- At least 2GB RAM available on host per microvm
- Required secrets configured in 1Password (specific to each microvm)

## Overview

By the end of this guide, you will have:
- A running MicroVM deployed from GitHub main
- Understanding of how to deploy different microvm types
- Verification that the microvm is functioning

## Steps

### 1. Identify the MicroVM to Deploy

Available microvms are defined in `flake.nix` under `microvm.nixosConfigurations`:

```bash
# List available microvms (run from flake directory or check GitHub)
nix flake show github:funkymonkeymonk/nix#microvm.nixosConfigurations
```

Common microvms:
- `dev-vm` - Development environment with base tools
- `matrix` - Matrix Synapse homeserver with Element Web
- `openclaw` - AI assistant gateway with Matrix integration

### 2. Ensure Secrets are Configured

Each microvm requires specific secrets in 1Password. Check the microvm's documentation:

- Matrix: See [Set up Matrix Synapse MicroVM](setup-matrix-microvm.md)
- OpenClaw: See [Set up OpenClaw MicroVM](setup-openclaw-microvm.md)

Verify the 1Password service account token is in place:

```bash
cat /etc/opnix/token
```

### 3. Build the MicroVM

Build directly from GitHub main without cloning:

```bash
# Replace MATRIX with your desired microvm name
cd ~/nix
nix build github:funkymonkeymonk/nix#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure
```

This downloads the flake from GitHub and builds the microvm. First build may take 10-30 minutes.

**Note**: The `--impure` flag is required because the microvm needs access to `/etc/opnix/token` at build time.

### 4. Run the MicroVM

Start the microvm:

```bash
nix run github:funkymonkeymonk/nix#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure
```

You will see:
- Boot messages
- Opnix syncing secrets from 1Password
- Services starting

Wait for the startup to complete (look for service ready messages).

### 5. Verify the MicroVM is Running

In another terminal on the host:

```bash
# List running microvms
ps aux | grep microvm

# Check network interfaces
ip addr show | grep microvm
```

SSH into the microvm:

```bash
# Replace with the microvm's hostname or IP
ssh root@matrix
# or
ssh root@10.0.2.15
```

### 6. Check Services

Inside the microvm, verify services are running:

```bash
# View running services
systemctl list-units --state=running

# Check specific service (replace with actual service name)
systemctl status matrix-synapse

# View logs
journalctl -f
```

### 7. Access the MicroVM Services

From your local machine, access the microvm's services:

```bash
# Port forward through the host
ssh -L 8080:localhost:80 user@your-server-ip

# Then open in browser or use curl
curl http://localhost:8080
```

Or access directly if the server is publicly accessible:

```bash
curl http://your-server-ip:8008
```

## Using a Specific Branch or PR

To deploy from a feature branch instead of main:

```bash
# Deploy from a specific branch
nix run github:funkymonkeymonk/nix/feat-branch-name#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure

# Deploy from a specific commit
nix run github:funkymonkeymonk/nix/abc123#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure
```

## Running Multiple MicroVMs

Each microvm runs in isolation. To run multiple:

1. Open multiple terminals
2. Run each microvm in its own terminal:

```bash
# Terminal 1
nix run github:funkymonkeymonk/nix#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure

# Terminal 2
nix run github:funkymonkeymonk/nix#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure
```

## Stopping the MicroVM

From the microvm console:

```bash
sudo shutdown now
```

Or from the host terminal running the microvm:

```bash
# Press Ctrl+C to stop
Ctrl+C
```

## Verification

Confirm the microvm deployed correctly:

```bash
# SSH into the microvm
ssh root@matrix

# Check the system
uname -a
cat /etc/os-release

# Verify secrets synced
ls -la /run/secrets/
```

## Troubleshooting

### Build fails with "cannot find flake"

Ensure the microvm name is correct:

```bash
# List available microvms
nix flake show github:funkymonkeymonk/nix 2>&1 | grep -A 10 "microvm.nixosConfigurations"
```

### Secrets not syncing

- Check Opnix logs: `journalctl -u onepassword-secrets -f`
- Verify token: `cat /etc/opnix/token`
- Ensure secrets exist in 1Password Homelab vault

### Cannot SSH into microvm

- Wait for boot to complete (can take 1-2 minutes)
- Check network: `ip addr show` inside the microvm
- Verify SSH service: `systemctl status sshd`

### Microvm exits immediately

Run with verbose output to see errors:

```bash
nix run github:funkymonkeymonk/nix#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure -- --show-trace
```

## Maintenance

### Update to Latest Main

Stop the microvm and restart with the latest main:

```bash
# Stop current microvm (Ctrl+C in its terminal)

# Re-run with latest main (nix automatically fetches updates)
nix run github:funkymonkeymonk/nix#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure
```

### Pin to a Specific Version

For reproducibility, pin to a specific commit:

```bash
# Get current commit hash
cd ~/nix && git rev-parse HEAD

# Use that commit in the URL
nix run github:funkymonkeymonk/nix/COMMIT_HASH#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure
```

## Next Steps

- [Set up Matrix Synapse MicroVM](setup-matrix-microvm.md) - Detailed Matrix setup
- [Set up OpenClaw MicroVM](setup-openclaw-microvm.md) - Detailed OpenClaw setup
- [Set up a MicroVM Host](setup-microvm-host.md) - Host configuration reference
- Create custom microvms by modifying files in `targets/microvms/`

## See Also

- [MicroVM.nix Documentation](https://github.com/astro/microvm.nix)
- [Nix Flakes Documentation](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html)
- [targets/microvms/](../../targets/microvms/) - MicroVM configuration files
