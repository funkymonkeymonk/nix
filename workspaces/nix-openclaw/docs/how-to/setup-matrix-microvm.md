# Set Up Matrix Synapse MicroVM

This guide shows you how to deploy a self-hosted Matrix Synapse homeserver in a MicroVM with Element Web client.

## Prerequisites

- [MicroVM host set up](setup-microvm-host.md)
- 1Password service account token placed at `/etc/opnix/token`
- Matrix Synapse secrets created in 1Password Homelab vault
- At least 2GB RAM available on host

## Overview

By the end of this guide, you will have:
- Matrix Synapse homeserver running in a MicroVM
- Element Web client accessible via web browser
- Admin and OpenClaw bot users created
- Federation-ready Matrix server

## Steps

### 1. Verify Secrets Exist in 1Password

Check that these items exist in your Homelab vault:

```bash
op item get "Matrix Synapse" --vault Homelab
```

Required fields:
- `signing-key` - Ed25519 signing key
- `registration-shared-secret` - Registration secret
- `admin-password` - Admin user password
- `openclaw-password` - OpenClaw bot password

If missing, see the item notes in 1Password for how to generate each.

### 2. Review and Update Secrets

View current values (rotate if needed):

```bash
# View admin password
op item get "Matrix Synapse" --vault Homelab --field admin-password --reveal

# View bot password  
op item get "Matrix Synapse" --vault Homelab --field openclaw-password --reveal
```

Save these passwords securely - you'll need them for first login.

### 3. Build the MicroVM

On your MicroVM host:

```bash
cd ~/nix
nix build .#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure
```

This may take 10-30 minutes on first run.

### 4. Run the Matrix MicroVM

Start the microvm:

```bash
nix run .#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure
```

You will see:
- Boot messages
- Opnix syncing secrets from 1Password
- Matrix Synapse starting
- User creation script running

Wait for the message: "Finished Matrix Synapse homeserver."

### 5. Verify Services are Running

In another terminal on the host, SSH into the microvm:

```bash
ssh root@matrix
# or if DNS not set up:
ssh root@10.0.2.15
```

Check services:

```bash
systemctl status matrix-synapse
systemctl status nginx
```

View logs:

```bash
journalctl -u matrix-synapse -f
```

### 6. Access Element Web

From your local machine:

```bash
# Port forward if needed
ssh -L 8080:localhost:80 user@your-server-ip

# Then open in browser:
open http://localhost:8080
```

Or if the server is directly accessible:

```
http://your-server-ip
```

### 7. Login as Admin

Use the admin password from step 2:

- **Username**: `@admin:matrix.local`
- **Password**: (from `admin-password` field)
- **Homeserver**: `http://localhost:8008` (or your server IP)

### 8. Create Rooms and Invite Bot

1. Create a new room in Element
2. Invite `@openclaw:matrix.local` to the room
3. The bot will join once OpenClaw microvm is running

### 9. Get OpenClaw Access Token (for OpenClaw setup)

This token is needed for the OpenClaw microvm:

```bash
# From your local machine or host
curl -X POST http://your-server-ip:8008/_matrix/client/r0/login \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "user": "openclaw",
    "password": "OPENCLAW_PASSWORD_HERE"
  }'
```

Save the `access_token` from the response.

Update 1Password with the token:

```bash
op item edit "OpenClaw" --vault Homelab \
  "matrix-access-token=syt_YOUR_TOKEN_HERE"
```

### 10. (Optional) Configure Federation

Edit `targets/microvms/matrix.nix` and adjust:

```nix
services.matrix-synapse.settings = {
  federation_domain_whitelist = [ "matrix.org" "example.com" ];
};
```

Rebuild and restart.

## Verification

Test the installation:

```bash
# Check server info
curl http://your-server-ip:8008/_matrix/federation/v1/version

# Check client API
curl http://your-server-ip:8008/_matrix/client/versions
```

Both should return JSON responses.

## Maintenance

### Rotate Secrets

```bash
# Update signing key
KEY=$(openssl rand -hex 32)
op item edit "Matrix Synapse" --vault Homelab \
  "signing-key=ed25519 a_auto $KEY"

# Restart microvm to pick up changes
```

### View Logs

```bash
ssh root@matrix
journalctl -u matrix-synapse -f
```

### Backup Database

```bash
ssh root@matrix
sqlite3 /var/lib/matrix-synapse/homeserver.db ".backup /tmp/backup.db"
scp root@matrix:/tmp/backup.db ./
```

## Troubleshooting

### Cannot login

- Verify admin-password in 1Password matches
- Check user was created: `synapse_admin list_users`
- View creation logs: `journalctl -u matrix-synapse-create-admin`

### Element Web shows "Cannot connect to homeserver"

- Check nginx is running: `systemctl status nginx`
- Verify homeserver URL in Element settings
- Check firewall: `iptables -L | grep 8008`

### Secrets not syncing

- Check Opnix: `journalctl -u onepassword-secrets -f`
- Verify token: `cat /etc/opnix/token`
- Check item exists: `op item get "Matrix Synapse" --vault Homelab`

## Next Steps

- [Set up OpenClaw MicroVM](setup-openclaw-microvm.md) - Connect AI assistant to Matrix
- Configure PostgreSQL instead of SQLite for production
- Set up reverse proxy with TLS (see [nginx](https://nginx.org/) or [traefik](https://traefik.io/))
- Enable federation with other Matrix servers

## See Also

- [Matrix Synapse Documentation](https://element-hq.github.io/synapse/latest/)
- [Element Web Documentation](https://element.io/)
- [targets/microvms/matrix.nix](../../targets/microvms/matrix.nix)
