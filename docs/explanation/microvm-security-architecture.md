# MicroVM Security Architecture

MicroVMs provide sandboxed environments for running untrusted workloads (like AI agents) with strong isolation from the host. This document explains the design decisions and security layers.

## Why MicroVMs

AI agents need access to tools and APIs, which means they need credentials. Running an agent on the host gives it access to everything on the system. Running it in a container gives it access to the host kernel and shared namespaces. A MicroVM runs its own kernel with hardware virtualization isolation — the same boundary used between cloud tenants.

## Design Decisions

### cloud-hypervisor over QEMU

QEMU is a full system emulator that happens to do virtualization. It has a large codebase and a correspondingly large attack surface. cloud-hypervisor is written in Rust, designed specifically for cloud workloads, and has a much smaller trusted computing base. The tradeoff is fewer device emulation options, but for NixOS guests we only need virtio-net, virtio-blk, and virtio-fs — all well-supported.

### Bridge Networking over User-mode NAT

User-mode networking (QEMU's SLIRP) gives zero visibility into what the VM is doing on the network. A bridge with TAP interfaces lets the host:
- Log every DNS query (via unbound)
- Log every new connection (via nftables)
- Apply firewall rules per-VM
- Assign static, predictable IPs

The tradeoff is more configuration complexity, but the visibility is essential for auditing agent behavior.

### Read-only Nix Store

The host's `/nix/store` is mounted read-only into each VM via virtiofs, with a writable overlay for any packages the VM needs to install. This prevents a compromised agent from tampering with system binaries. The overlay is discarded when the VM restarts.

### Two-level Cloud-init

The cloud-init design separates concerns:

1. **Host-level** (`/etc/cloud-init.yaml`) — defines which VMs exist. This is the single source of truth that the operator manages via `nix-cloud-init`.

2. **Per-VM** (`/etc/cloud-init/<hostname>.yaml`) — generated at build time from the Nix configuration. These are mounted into each VM via virtiofs and contain hostname and eventually secrets/onecli config.

This separation means the operator manages one file, and the build system generates the per-VM files with the correct structure. It also means cloud-init files are part of the Nix store — they're reproducible and version-controlled.

### opnix in VMs (for now)

Each VM runs its own opnix instance with a 1Password service account token. This is simpler than host-side secret staging and gives each VM independent secret management. The downside is that each VM has access to the 1Password token, which expands the attack surface.

The planned replacement is [onecli](https://github.com/onecli/onecli), a credential gateway that intercepts HTTP requests and injects credentials. Agents would use placeholder keys and never see real secrets.

## Security Layers

```
┌─────────────────────────────────────────────────────┐
│  Layer 1: Hardware Virtualization                   │
│  Each VM has its own kernel, isolated from host     │
│  cloud-hypervisor (Rust, minimal TCB)               │
├─────────────────────────────────────────────────────┤
│  Layer 2: Read-only Nix Store                       │
│  VMs can't modify system binaries                   │
│  Writable overlay discarded on reboot               │
├─────────────────────────────────────────────────────┤
│  Layer 3: Network Monitoring                        │
│  All DNS queries logged (unbound)                   │
│  All new connections logged (nftables)              │
│  NAT masquerade, no direct external access          │
├─────────────────────────────────────────────────────┤
│  Layer 4: Systemd Hardening                         │
│  NoNewPrivileges, ProtectSystem=strict, etc.        │
│  Configurable per-service                           │
├─────────────────────────────────────────────────────┤
│  Layer 5: Secret Management                         │
│  1Password via opnix (current)                      │
│  onecli credential gateway (planned)                │
└─────────────────────────────────────────────────────┘
```

## Threat Model

### What We Protect Against

- **Agent exfiltration** — DNS and connection logging detect unusual outbound traffic
- **Privilege escalation** — Systemd hardening prevents the agent process from gaining additional privileges
- **Binary tampering** — Read-only Nix store prevents modification of system binaries
- **Lateral movement** — Each VM is isolated on the bridge; VMs can only reach each other through explicit firewall rules
- **Secret exposure** — Secrets are read from 1Password at runtime, not stored in configuration files

### What We Don't Protect Against

- **Host compromise** — If the host is compromised, the VMs are not safe
- **Kernel vulnerabilities** — A VM could exploit a KVM or kernel vulnerability to escape
- **Supply chain attacks** — If a Nix package is malicious, it runs inside the VM
- **Social engineering** — An agent could still be tricked into making API calls on behalf of an attacker

## Alternatives Considered

### Containers (Docker/Podman)

Containers share the host kernel and namespaces. A container escape gives full host access. MicroVMs have their own kernel, so an escape requires a hypervisor vulnerability — a much higher bar.

### Host-side Secret Staging

The blog post approach stages secrets on the host and mounts them into VMs. This removes 1Password from the VM entirely. We chose to keep opnix in VMs because:
1. It's simpler to set up (no custom staging scripts)
2. Each VM can have independent secret access
3. The onecli plan provides better isolation anyway

### sops-nix

sops-nix encrypts secrets with age/GPG keys stored on the host. This avoids needing 1Password in VMs but introduces key management complexity. We use 1Password because it's already in use for the homelab and supports audit logging.

> For a walkthrough, see [Manage MicroVMs](../how-to/manage-microvms.md).
> For module details, see [MicroVM Modules Reference](../reference/microvm-modules.md).
