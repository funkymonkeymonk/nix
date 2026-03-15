# Set Up a MicroVM Host

This guide shows you how to configure a server as a MicroVM host for running isolated NixOS virtual machines.

## Prerequisites

- A server running NixOS (x86_64-linux)
- SSH access to the server
- Sudo privileges
- At least 8GB RAM and 50GB disk space

## Overview

By the end of this guide, you will have:
- A NixOS server configured as a MicroVM host
- The ability to run multiple isolated microvms
- Network connectivity between host and microvms
- Basic microvm for experimentation

## Steps

### 1. Prepare the Server

Connect to your NixOS server:

```bash
ssh user@your-server-ip
```

Ensure the server is up to date:

```bash
sudo nixos-rebuild switch --upgrade
```

### 2. Enable KVM Virtualization

Check if KVM is enabled:

```bash
lsmod | grep kvm
```

You should see `kvm` and `kvm_intel` or `kvm_amd`.

If not enabled, add to your server's configuration:

```nix
# /etc/nixos/configuration.nix
boot.kernelModules = [ "kvm-intel" ];
# or for AMD:
# boot.kernelModules = [ "kvm-amd" ];
```

Rebuild and reboot:

```bash
sudo nixos-rebuild switch
sudo reboot
```

### 3. Clone the Repository

On the server, clone your nix configuration:

```bash
git clone https://github.com/funkymonkeymonk/nix.git ~/nix
cd ~/nix
```

### 4. Place 1Password Service Account Token

Create the service account token file:

```bash
sudo mkdir -p /etc/opnix
echo "ops_your_service_account_token" | sudo tee /etc/opnix/token
sudo chmod 600 /etc/opnix/token
```

**Important**: Get this token from your 1Password service account (see [Set up 1Password](setup-1password.md)).

### 5. Build and Run a Base MicroVM

Test with the dev-vm microvm:

```bash
cd ~/nix
nix run .#microvm.nixosConfigurations.dev-vm.config.microvm.declarationRunner --impure
```

The microvm will start and you should see boot messages.

### 6. Access the MicroVM

In another terminal, SSH into the running microvm:

```bash
ssh dev@localhost -p 2222
# Password: dev (or check the microvm configuration)
```

Or use the serial console:

```bash
# From the terminal running the microvm, you have direct console access
```

### 7. Verify Network Connectivity

Inside the microvm, test network:

```bash
ping 8.8.8.8
ip addr show
```

### 8. Stop the MicroVM

From the microvm console:

```bash
sudo shutdown now
```

Or from the host, press `Ctrl+C` in the terminal running the microvm.

## Next Steps

Now that you have a working MicroVM host, you can:

- **Set up specific microvms**:
  - [Set up Matrix Synapse MicroVM](setup-matrix-microvm.md) - Self-hosted chat server
  - [Set up OpenClaw MicroVM](setup-openclaw-microvm.md) - AI assistant with Matrix integration

- **Create custom microvms** by copying and modifying `targets/microvms/dev-vm.nix`

- **Configure auto-start** by adding microvms to your host's systemd services

## Troubleshooting

### MicroVM fails to start

Check KVM is enabled:
```bash
sudo dmesg | grep -i kvm
```

### Cannot SSH into microvm

Check the microvm is running and port mapping:
```bash
sudo netstat -tlnp | grep 2222
```

### No network in microvm

Ensure the host has IP forwarding enabled:
```bash
sudo sysctl net.ipv4.ip_forward
# Should be 1
```

## See Also

- [MicroVM.nix Documentation](https://github.com/astro/microvm.nix)
- [Add a new machine](add-machine.md)
- [NixOS MicroVMs Reference](../reference/microvms.md) (coming soon)
