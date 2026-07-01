---
title: "How to Manage MicroVMs"
description: "Add, remove, start, stop, and update NixOS MicroVMs on a type-server"
type: how-to
audience: both
last-reviewed: 2026-06-30
---

# How to Manage MicroVMs

Manage lightweight NixOS MicroVMs running on a `type-server` with the `microvm-host` role enabled.

## Add a MicroVM

1. Choose a name, flake attribute, and IP address for the VM:

    ```bash
    # Syntax: add <name> <flake-attr> <ip-address> [autoStart]
    sudo nix-cloud-init microvm add matrix .#microvm.nixosConfigurations.matrix 192.168.83.15
    sudo nix-cloud-init microvm add openclaw .#microvm.nixosConfigurations.openclaw 192.168.83.16
    ```

    `autoStart` defaults to `true`.

2. Regenerate the Nix configuration:

    ```bash
    sudo nix-cloud-init microvm generate
    ```

    This writes disk interfaces, cloud-hypervisor configs, read-only store mounts, and cloud-init shares into `/etc/nixos/microvms.nix`.

3. Rebuild the system:

    ```bash
    sudo nixos-rebuild switch --impure
    ```

## Remove a MicroVM

1. Delete the definition:

    ```bash
    sudo nix-cloud-init microvm remove matrix
    ```

2. Regenerate and rebuild:

    ```bash
    sudo nix-cloud-init microvm generate
    sudo nixos-rebuild switch --impure
    ```

## List Defined MicroVMs

```bash
sudo nix-cloud-init microvm list
```

## Start / Stop / Restart Individual VMs

Each MicroVM runs as a systemd service named `microvm-\u003cname\u003e`:

```bash
sudo systemctl start  microvm-matrix
sudo systemctl stop   microvm-openclaw
sudo systemctl restart microvm-matrix
```

## Check VM Status

```bash
sudo systemctl status microvm-matrix
```

## SSH Into a VM

Connect from the host using the IP address you assigned:

```bash
ssh root@192.168.83.15   # Matrix
ssh root@192.168.83.16  # OpenClaw
```

## View Monitoring Data

- **DNS queries** from VMs flow through unbound:

    ```bash
    journalctl -u unbound -f
    ```

- **Outbound connections** appear in the kernel log:

    ```bash
    journalctl -k | grep microvm-egress
    ```

\u003e For cloud-init format details, see [Cloud-init Format Reference](../reference/cloud-init-format.md).
