# MicroVM Security Architecture

## Overview

MicroVMs are sandboxed environments for running untrusted workloads (like OpenClaw) with strong isolation from the host. The `microvm-host` role can be enabled on any `type-server` via cloud-init.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     type-server + microvm-host role               │
│                                                                  │
│  /etc/cloud-init.yaml defines which VMs run:                    │
│  microvms:                                                       │
│    - name: matrix                                                │
│      flake: .#microvm.nixosConfigurations.matrix                 │
│      ipAddress: 192.168.83.15                                    │
│      autoStart: true                                             │
│    - name: openclaw                                              │
│      flake: .#microvm.nixosConfigurations.openclaw               │
│      ipAddress: 192.168.83.16                                    │
│      autoStart: true                                             │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Bridge: microbr (192.168.83.1/24)           │    │
│  │              NAT → external interface                    │    │
│  │              unbound: DNS logging                        │    │
│  │              nftables: connection logging                │    │
│  └──────────┬──────────────────────────┬────────────────────┘    │
│             │ TAP                      │ TAP                      │
│  ┌──────────▼──────────┐  ┌───────────▼──────────────┐          │
│  │  Matrix MicroVM     │  │  OpenClaw MicroVM         │          │
│  │  192.168.83.15      │  │  192.168.83.16            │          │
│  │                      │  │                           │          │
│  │  • Synapse :8008     │  │  • OpenClaw Gateway :18789│          │
│  │  • Element Web :80   │  │  • Matrix Bot             │          │
│  │  • opnix → 1Password │  │  • opnix → 1Password      │          │
│  │  • cloud-hypervisor  │  │  • cloud-hypervisor       │          │
│  │  • ro-store + overlay│  │  • ro-store + overlay     │          │
│  │  • Systemd hardening │  │  • Systemd hardening      │          │
│  └──────────────────────┘  └───────────────────────────┘          │
│                                                                    │
│  Secrets: opnix (1Password) on host AND in each VM                │
│  Future: onecli for VM secret injection                           │
└──────────────────────────────────────────────────────────────────┘
```

## Security Layers

### 1. Hypervisor Isolation

- **cloud-hypervisor** — Rust-based, minimal attack surface, designed for microvms
- Each VM runs its own kernel, reducing attack surface vs containers
- Sub-100MB memory overhead, single-digit second boot times

### 2. Read-Only Nix Store

- Host `/nix/store` mounted read-only via virtiofs
- VMs get a writable overlay at `/nix/.rw-store`
- Prevents tampering with system binaries

### 3. Bridge Networking with Monitoring

- **TAP interfaces** on a dedicated bridge (`microbr`, `192.168.83.0/24`)
- **DNS logging** — unbound logs every query from microvms
- **Connection logging** — nftables logs every new outbound connection
- NAT masquerade for internet access

### 4. Secrets from 1Password

- **Host**: opnix reads from 1Password via service account token at `/etc/opnix-token`
- **VMs**: Each VM also runs opnix with its own `/etc/opnix-token` for direct 1Password access
- **Future**: [onecli](https://github.com/onecli/onecli) — credential gateway where agents never see raw keys

### 5. Cloud-Init VM Discovery

- `/etc/cloud-init.yaml` contains a `microvms:` section defining which VMs to run
- `microvm-discover` service reads cloud-init at boot, generates per-VM cloud-init files, and starts each VM via systemd
- Add/remove VMs with `nix-cloud-init microvm add/remove`

### 6. Systemd Hardening (OpenClaw Service)

Configurable hardening options with safe defaults:

| Directive | Default | Notes |
|-----------|---------|-------|
| `NoNewPrivileges` | true | Prevent privilege escalation |
| `ProtectSystem` | strict | Read-only filesystem except data dir |
| `ProtectHome` | read-only | Can read but not write home dirs |
| `PrivateTmp` | true | Private /tmp and /var/tmp |
| `ProtectKernelTunables` | true | Kernel params read-only |
| `ProtectKernelModules` | true | No module loading |
| `ProtectControlGroups` | true | cgroup tree read-only |
| `RestrictSUIDSGID` | true | No SUID/SGID files |
| `RestrictAddressFamilies` | null | Set to `["AF_INET" "AF_INET6" "AF_NETLINK"]` for microvms |
| `LockPersonality` | true | Lock execution domain |

## Enabling the microvm-host Role

### Via cloud-init

```bash
# On a type-server, enable the role
sudo nix-cloud-init set nix.roles microvm-host

# Add microvm definitions
sudo nix-cloud-init microvm add matrix .#microvm.nixosConfigurations.matrix 192.168.83.15
sudo nix-cloud-init microvm add openclaw .#microvm.nixosConfigurations.openclaw 192.168.83.16

# Rebuild
sudo nixos-rebuild switch --flake github:funkymonkeymonk/nix#type-server --impure
```

### Via nix configuration

Add to your machine config:

```nix
myConfig.roles.microvm-host.enable = true;
```

The cloud-init `microvms:` section controls which VMs run:

```yaml
microvms:
  - name: matrix
    flake: .#microvm.nixosConfigurations.matrix
    ipAddress: 192.168.83.15
    autoStart: true
  - name: openclaw
    flake: .#microvm.nixosConfigurations.openclaw
    ipAddress: 192.168.83.16
    autoStart: true
```

## Managing MicroVMs

```bash
# List defined microvms
nix-cloud-init microvm list

# Add a microvm
sudo nix-cloud-init microvm add <name> <flake-attr> <ip-address> [autoStart]

# Remove a microvm
sudo nix-cloud-init microvm remove <name>

# Start/stop individual VMs
sudo systemctl start microvm-matrix
sudo systemctl stop microvm-openclaw

# Check status
sudo systemctl status microvm-matrix

# View monitoring
journalctl -u unbound -f              # DNS queries
journalctl -k | grep microvm-egress   # Connections
```

## Secrets Setup

### Host (opnix)

```bash
# Place 1Password service account token
echo "your-token" | sudo tee /etc/opnix-token
sudo chmod 600 /etc/opnix-token
```

### Inside each VM

After SSH-ing into a VM:

```bash
ssh root@192.168.83.15  # Matrix
ssh root@192.168.83.16  # OpenClaw

# Place 1Password service account token (same or separate token)
echo "your-token" | sudo tee /etc/opnix-token
sudo chmod 600 /etc/opnix-token

# Restart opnix to sync secrets
sudo systemctl restart onepassword-secrets
```

### Required 1Password Items

**Matrix Synapse** (`op://Homelab/Matrix Synapse/`):
- `signing-key` — Ed25519 signing key
- `registration-shared-secret` — Shared secret for user registration
- `admin-password` — Admin user password
- `openclaw-password` — OpenClaw bot password

**OpenClaw** (`op://Homelab/OpenClaw/`):
- `zen-api-key` — OpenCode Zen API key
- `matrix-access-token` — Matrix bot access token (get after Matrix starts)

## Comparison: Before vs After

| Aspect | Before | After |
|--------|--------|-------|
| Hypervisor | QEMU | cloud-hypervisor |
| Networking | User-mode NAT | TAP + bridge |
| DNS visibility | None | unbound logs all queries |
| Connection visibility | None | nftables logs all connections |
| Nix store | Read-write | Read-only + overlay |
| Secrets | opnix in VMs | opnix in VMs (onecli planned) |
| Systemd hardening | Fixed | Configurable options |
| Boot management | Manual | cloud-init discovery |
| Role pattern | Separate target | Composable role on type-server |
