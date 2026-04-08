# MicroVM Modules Reference

Reference for the NixOS modules that implement MicroVM hosting.

## microvm-host Role

**Module:** `modules/roles/microvm-host.nix`

Enables MicroVM host infrastructure on any NixOS system.

### Activation

```nix
myConfig.roles.microvm-host.enable = true;
```

Or via cloud-init:

```bash
sudo nix-cloud-init set nix.roles microvm-host
```

### What It Does

- Imports `modules/services/microvm-host`
- Enables `services.microvm-host.enable`
- Loads KVM kernel modules
- Installs `cloud-hypervisor` and `virtiofsd`
- Generates per-VM cloud-init files at `/etc/cloud-init/<hostname>.yaml`

### Requirements

The host configuration must also import `microvm.nixosModules.microvm` (already done in `type-server` and `type-server-arm` flake targets).

### Per-VM Cloud-init Generation

At build time, the role generates one cloud-init file per VM defined in `config.microvm.vms`. Each file contains:

```yaml
#cloud-config
hostname: <name>
```

Files are placed at `/etc/cloud-init/<hostname>.yaml` on the host and mounted into each VM via virtiofs.

## microvm-host Service

**Module:** `modules/services/microvm-host/default.nix`

Provides bridge networking, DNS logging, and connection monitoring.

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.microvm-host.enable` | bool | `false` | Enable the service |
| `services.microvm-host.bridgeName` | string | `"microbr"` | Bridge interface name |
| `services.microvm-host.bridgeSubnet` | string | `"192.168.83.1/24"` | Bridge subnet (CIDR) |
| `services.microvm-host.externalInterface` | nullOr string | `null` | External interface for NAT. Null = auto-detect |
| `services.microvm-host.dnsForwarders` | list of string | `["8.8.8.8" "1.1.1.1"]` | Upstream DNS servers |
| `services.microvm-host.logQueries` | bool | `true` | Log DNS queries via unbound |
| `services.microvm-host.logConnections` | bool | `true` | Log connections via nftables |

### What It Configures

- **Bridge networking** — `systemd.network` creates a bridge and attaches TAP interfaces
- **NAT** — `networking.nat` masquerades VM traffic to the external interface
- **DNS logging** — `services.unbound` with `log-queries = "yes"`
- **Connection logging** — `networking.nftables` logs new connections from the bridge
- **Packages** — `cloud-hypervisor`, `virtiofsd`

## MicroVM Guest Module

**Module:** `modules/microvm/default.nix`

Configures networking and cloud-init consumption inside each VM.

### What It Configures

- **Networking** — Static IP on `eth0` from `myConfig.microvm.ipAddress`, gateway from `myConfig.microvm.gateway`, DNS `192.168.83.1`
- **Cloud-init** — Reads hostname from `/etc/cloud-init/<hostname>.yaml` at boot
- **SSH** — Enabled, root key-only, password auth disabled
- **Packages** — `vim`, `git`, `htop`, `curl`

## MicroVM Targets

**Location:** `targets/microvms/`

| Target | Description |
|--------|-------------|
| `matrix.nix` | Matrix Synapse server with Element Web, nginx proxy, opnix secrets |
| `openclaw.nix` | OpenClaw AI gateway with Matrix channel, opnix secrets, systemd hardening |
| `dev-vm.nix` | Development environment with opencode role |

### Common Options

Each target sets:

| Option | Description |
|--------|-------------|
| `networking.hostName` | VM hostname |
| `myConfig.microvm.enable` | Marks as a microvm guest |
| `myConfig.microvm.ipAddress` | Static IP on the bridge |
| `myConfig.microvm.gateway` | Gateway IP (bridge IP) |
| `services.onepassword-secrets` | 1Password secret definitions |

> For cloud-init format details, see [Cloud-init Format Reference](../reference/cloud-init-format.md).
> For the security architecture, see [MicroVM Security Architecture](../explanation/microvm-security-architecture.md).
