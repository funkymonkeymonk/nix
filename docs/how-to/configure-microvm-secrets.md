# Configure MicroVM Secrets

Set up 1Password secrets for MicroVMs running on a type-server.

## Host Secrets

Place the 1Password service account token on the host:

```bash
echo "your-token" | sudo tee /etc/opnix-token
sudo chmod 600 /etc/opnix-token
```

## VM Secrets

Each VM runs its own opnix instance. SSH into each VM and place the token:

```bash
ssh root@192.168.83.15  # Matrix
echo "your-token" | sudo tee /etc/opnix-token
sudo chmod 600 /etc/opnix-token
sudo systemctl restart onepassword-secrets
```

Repeat for each VM.

## Required 1Password Items

### Matrix Synapse

Vault: `Homelab`, Item: `Matrix Synapse`

| Field | Path | Used By |
|-------|------|---------|
| `signing-key` | `op://Homelab/Matrix Synapse/signing-key` | Matrix VM |
| `registration-shared-secret` | `op://Homelab/Matrix Synapse/registration-shared-secret` | Matrix VM |
| `admin-password` | `op://Homelab/Matrix Synapse/admin-password` | Matrix VM |
| `openclaw-password` | `op://Homelab/Matrix Synapse/openclaw-password` | Matrix VM |

### OpenClaw

Vault: `Homelab`, Item: `OpenClaw`

| Field | Path | Used By |
|-------|------|---------|
| `zen-api-key` | `op://Homelab/OpenClaw/zen-api-key` | OpenClaw VM |
| `matrix-access-token` | `op://Homelab/OpenClaw/matrix-access-token` | OpenClaw VM |

## Getting the Matrix Access Token

After the Matrix VM starts, log in as the OpenClaw bot user:

```bash
ssh root@192.168.83.16
curl -X POST http://192.168.83.15:8008/_matrix/client/r0/login \
  -H "Content-Type: application/json" \
  -d '{"type":"m.login.password","user":"openclaw","password":"<openclaw-password>"}'
```

Save the `access_token` from the response to 1Password, then restart OpenClaw:

```bash
sudo systemctl restart openclaw-gateway
```

## Future: onecli

The plan is to replace opnix in VMs with [onecli](https://github.com/onecli/onecli), a credential gateway where agents never see raw keys. The onecli gateway intercepts HTTP requests and injects credentials transparently.

> For a step-by-step walkthrough, see [Run OpenClaw in a MicroVM](../tutorials/run-openclaw-microvm.md).
> For the security architecture, see [MicroVM Security Architecture](../explanation/microvm-security-architecture.md).
