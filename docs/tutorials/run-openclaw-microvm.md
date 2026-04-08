# Run OpenClaw in a MicroVM on type-server

In this tutorial you will set up OpenClaw (an AI assistant) running inside a sandboxed MicroVM on your type-server, with Matrix chat integration and full network monitoring.

## Prerequisites

- A `type-server` running NixOS with KVM support (Intel VT-x or AMD-V enabled in BIOS)
- 1Password service account token with access to the `Homelab` vault
- SSH access to the server as a user in the `wheel` group

## Step 1: Enable the microvm-host role

SSH into your type-server and enable the role:

```bash
sudo nix-cloud-init set nix.roles microvm-host
```

Verify the role is set:

```bash
nix-cloud-init show
```

You should see `microvm-host` in the roles section.

## Step 2: Add the Matrix microvm

OpenClaw needs a Matrix server to chat through. Add it first:

```bash
sudo nix-cloud-init microvm add matrix .#microvm.nixosConfigurations.matrix 192.168.83.15
```

## Step 3: Add the OpenClaw microvm

```bash
sudo nix-cloud-init microvm add openclaw .#microvm.nixosConfigurations.openclaw 192.168.83.16
```

Verify both are defined:

```bash
nix-cloud-init microvm list
```

You should see:
```
matrix
openclaw
```

## Step 4: Generate the Nix configuration

This creates `/etc/nixos/microvms.nix` from your cloud-init definitions:

```bash
sudo nix-cloud-init microvm generate
```

You should see:
```
SUCCESS: Generated /etc/nixos/microvms.nix with 2 microvm(s)
INFO: Run 'sudo nixos-rebuild switch' to apply
```

## Step 5: Place your 1Password token

```bash
echo "your-1password-service-account-token" | sudo tee /etc/opnix-token
sudo chmod 600 /etc/opnix-token
```

## Step 6: Rebuild the host

```bash
sudo nixos-rebuild switch --impure
```

This will:
1. Build the host configuration with bridge networking, DNS logging, and connection monitoring
2. Generate per-VM cloud-init files
3. Start the Matrix microvm
4. Start the OpenClaw microvm

## Step 7: Create Matrix users

After the Matrix VM starts (wait ~30 seconds), create the admin and bot users:

```bash
ssh root@192.168.83.15
systemctl status matrix-synapse
```

If the service is running, the users are created automatically from secrets.

## Step 8: Get the OpenClaw Matrix token

Log into Matrix as the `openclaw` user to get an access token:

```bash
curl -X POST http://192.168.83.15:8008/_matrix/client/r0/login \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"openclaw","password":"<password-from-1password>"}'
```

Save the `access_token` from the response to 1Password:

```bash
op item edit "OpenClaw" --vault Homelab "matrix-access-token=<token-from-response>"
```

## Step 9: Set your Zen API key

```bash
op item edit "OpenClaw" --vault Homelab "zen-api-key=zen_YOUR_KEY"
```

Then restart OpenClaw inside the VM:

```bash
ssh root@192.168.83.16
sudo systemctl restart openclaw-gateway
```

## Step 10: Verify everything works

Check the OpenClaw service:

```bash
ssh root@192.168.83.16
journalctl -u openclaw-gateway -f
```

You should see the gateway starting and connecting to Matrix.

Open Element Web at `http://192.168.83.15` and create a room. Invite `@openclaw:matrix.local` and start chatting.

## What you've set up

- **Bridge networking** — both VMs on `192.168.83.0/24` with NAT to the internet
- **DNS logging** — all queries from VMs are logged via unbound
- **Connection logging** — all outbound connections are logged via nftables
- **Read-only Nix store** — VMs can't tamper with system binaries
- **1Password secrets** — each VM reads its own secrets via opnix

> For details on managing VMs, see [Manage MicroVMs](../how-to/manage-microvms.md).
> For the security architecture, see [MicroVM Security Architecture](../explanation/microvm-security-architecture.md).
> For cloud-init format details, see [Cloud-init Format Reference](../reference/cloud-init-format.md).
