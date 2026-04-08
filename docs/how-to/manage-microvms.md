# Manage MicroVMs

Add, remove, start, and stop MicroVMs on a type-server with the `microvm-host` role enabled.

## Add a MicroVM

```bash
sudo nix-cloud-init microvm add <name> <flake-attr> <ip-address> [autoStart]
```

Example:

```bash
sudo nix-cloud-init microvm add matrix .#microvm.nixosConfigurations.matrix 192.168.83.15
sudo nix-cloud-init microvm add openclaw .#microvm.nixosConfigurations.openclaw 192.168.83.16
```

The `autoStart` parameter defaults to `true`.

## Remove a MicroVM

```bash
sudo nix-cloud-init microvm remove <name>
```

Example:

```bash
sudo nix-cloud-init microvm remove matrix
```

Then regenerate and rebuild:

```bash
sudo nix-cloud-init microvm generate
sudo nixos-rebuild switch --impure
```

## List Defined MicroVMs

```bash
nix-cloud-init microvm list
```

## Generate Nix Configuration

After adding or removing VMs, regenerate `/etc/nixos/microvms.nix`:

```bash
sudo nix-cloud-init microvm generate
```

This file defines `microvm.vms.*` with TAP interfaces, cloud-hypervisor, read-only store, and cloud-init shares.

## Start/Stop Individual VMs

```bash
sudo systemctl start microvm-matrix
sudo systemctl stop microvm-openclaw
sudo systemctl restart microvm-matrix
```

## Check VM Status

```bash
sudo systemctl status microvm-matrix
sudo systemctl status microvm-openclaw
```

## SSH Into a VM

From the host:

```bash
ssh root@192.168.83.15  # Matrix
ssh root@192.168.83.16  # OpenClaw
```

## View Monitoring

### DNS queries from VMs

```bash
journalctl -u unbound -f
```

### Outbound connections from VMs

```bash
journalctl -k | grep microvm-egress
```

## Enable the microvm-host Role

If not already enabled:

```bash
sudo nix-cloud-init set nix.roles microvm-host
sudo nixos-rebuild switch --impure
```

> For a step-by-step walkthrough, see [Run OpenClaw in a MicroVM](../tutorials/run-openclaw-microvm.md).
> For cloud-init format details, see [Cloud-init Format Reference](../reference/cloud-init-format.md).
