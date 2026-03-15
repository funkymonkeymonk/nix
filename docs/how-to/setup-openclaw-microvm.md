# Set Up OpenClaw MicroVM

This guide shows you how to deploy OpenClaw AI assistant in a MicroVM, connected to your Matrix server.

## Prerequisites

- [MicroVM host set up](setup-microvm-host.md)
- [Matrix Synapse microvm running](setup-matrix-microvm.md)
- 1Password service account token at `/etc/opnix/token`
- OpenClaw secrets created in 1Password Homelab vault
- Matrix access token obtained from Matrix setup
- OpenCode Zen API key from your provider
- At least 2GB RAM available on host

## Overview

By the end of this guide, you will have:
- OpenClaw AI assistant running in a MicroVM
- Bot connected to Matrix server
- Ability to chat with AI in Matrix rooms
- Environment files generated from 1Password secrets

## Steps

### 1. Verify Prerequisites

Ensure Matrix is running and accessible:

```bash
# From MicroVM host
curl http://matrix:8008/_matrix/client/versions
# Should return JSON with versions
```

Verify OpenClaw secrets exist:

```bash
op item get "OpenClaw" --vault Homelab
```

Required fields:
- `zen-api-key` - Your OpenCode Zen API key
- `matrix-access-token` - Bot access token (obtained from Matrix)

### 2. Get OpenCode Zen API Key

Contact your OpenCode Zen provider and request an API key.

Once received, update 1Password:

```bash
op item edit "OpenClaw" --vault Homelab \
  "zen-api-key=zen_YOUR_REAL_KEY_HERE"
```

### 3. Get Matrix Access Token

If you haven't already obtained this from Matrix setup:

```bash
# Get the OpenClaw password from 1Password
op item get "Matrix Synapse" --vault Homelab \
  --field openclaw-password --reveal

# Login to get access token
curl -X POST http://matrix:8008/_matrix/client/r0/login \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "user": "openclaw",
    "password": "PASSWORD_FROM_ABOVE"
  }'
```

Save the `access_token` value (starts with `syt_`).

Update 1Password:

```bash
op item edit "OpenClaw" --vault Homelab \
  "matrix-access-token=syt_YOUR_TOKEN_HERE"
```

### 4. Verify Both Secrets Are Set

```bash
op item get "OpenClaw" --vault Homelab --field zen-api-key --reveal
op item get "OpenClaw" --vault Homelab --field matrix-access-token --reveal
```

Both should show your real values (not placeholders).

### 5. Build the MicroVM

On your MicroVM host:

```bash
cd ~/nix
nix build .#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure
```

This may take 10-30 minutes on first run.

### 6. Run the OpenClaw MicroVM

Start the microvm:

```bash
nix run .#microvm.nixosConfigurations.openclaw.config.microvm.declarationRunner --impure
```

You will see:
- Boot messages
- Opnix syncing secrets
- Environment file being generated
- OpenClaw gateway starting

Wait for: "OpenClaw Gateway listening on port 18789"

### 7. Verify Services

In another terminal, SSH into the microvm:

```bash
ssh root@openclaw
# or:
ssh root@10.0.2.16
```

Check services:

```bash
# Check environment file generation
systemctl status openclaw-generate-env
cat /run/openclaw/generated-env

# Check OpenClaw gateway
systemctl status openclaw-gateway
journalctl -u openclaw-gateway -f
```

### 8. Test Matrix Connection

The bot should automatically join rooms where it's invited.

From Element Web:
1. Go to a room where you invited `@openclaw:matrix.local`
2. Send a message: "Hello OpenClaw!"
3. The bot should respond using the Zen API

### 9. Verify AI Responses

Check OpenClaw logs for activity:

```bash
ssh root@openclaw
journalctl -u openclaw-gateway -f
```

You should see:
- Matrix message received
- API call to Zen
- Response sent back to Matrix

## Verification

Test the complete flow:

```bash
# 1. Check OpenClaw is running
ssh root@openclaw
systemctl is-active openclaw-gateway

# 2. Check environment file exists
cat /run/openclaw/generated-env | grep ZEN_API_KEY

# 3. Check Matrix connection
journalctl -u openclaw-gateway | grep -i "connected\|matrix"

# 4. Send test message from Element and watch logs
journalctl -u openclaw-gateway -f
```

## Using OpenClaw

### Basic Usage

In any Matrix room with the bot:

```
@openclaw:matrix.local What is the weather today?
```

Or if the bot is the only member:

```
What is the weather today?
```

### Available Commands

OpenClaw supports various commands (see [OpenClaw docs](https://docs.openclaw.ai)):

```
/status - Show current session status
/reset - Reset conversation context
/compact - Compact conversation history
```

## Maintenance

### Rotate Zen API Key

If your API key expires or is compromised:

```bash
# Get new key from provider
op item edit "OpenClaw" --vault Homelab \
  "zen-api-key=zen_YOUR_NEW_KEY"

# Restart OpenClaw microvm
# New key will be picked up automatically
```

### Regenerate Matrix Token

If the token is invalidated:

```bash
# Login again to get new token
curl -X POST http://matrix:8008/_matrix/client/r0/login ...

# Update 1Password
op item edit "OpenClaw" --vault Homelab \
  "matrix-access-token=syt_NEW_TOKEN"

# Restart OpenClaw microvm
```

### View Logs

```bash
# Environment generation
ssh root@openclaw
journalctl -u openclaw-generate-env -f

# Gateway
journalctl -u openclaw-gateway -f

# All OpenClaw logs
journalctl -u 'openclaw-*' -f
```

## Troubleshooting

### Bot doesn't respond

1. Check OpenClaw is running:
   ```bash
   ssh root@openclaw
   systemctl status openclaw-gateway
   ```

2. Verify environment file:
   ```bash
   cat /run/openclaw/generated-env
   # Should show ZEN_API_KEY and OPENCLAW_MATRIX_ACCESS_TOKEN
   ```

3. Check logs for errors:
   ```bash
   journalctl -u openclaw-gateway -f
   ```

### Cannot connect to Matrix

1. Verify Matrix is running:
   ```bash
   curl http://matrix:8008/_matrix/client/versions
   ```

2. Check token is valid:
   ```bash
   curl -H "Authorization: Bearer syt_YOUR_TOKEN" \
     http://matrix:8008/_matrix/client/r0/account/whoami
   ```

3. Regenerate token if needed (see step 3)

### Zen API errors

1. Verify API key is valid:
   ```bash
   # Check the key in 1Password
   op item get "OpenClaw" --vault Homelab --field zen-api-key --reveal
   ```

2. Contact Zen provider if key is expired

3. Check rate limits in logs

### Secrets not syncing

1. Check Opnix service:
   ```bash
   ssh root@openclaw
   journalctl -u onepassword-secrets -f
   ```

2. Verify service account token:
   ```bash
   cat /etc/opnix/token
   ```

3. Check secrets exist:
   ```bash
   ls -la /run/secrets/
   ```

## Architecture

How it works:

1. **Opnix** syncs individual secrets from 1Password to `/run/secrets/`
2. **openclaw-generate-env** service reads secrets and composes environment file
3. **openclaw-gateway** service uses environment file for configuration
4. Bot connects to Matrix and responds to messages using Zen API

## Next Steps

- Invite OpenClaw to multiple rooms
- Configure additional channels (Telegram, Discord, etc.)
- Customize OpenClaw behavior via configuration
- Set up monitoring for the microvm

## See Also

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [Matrix Client-Server API](https://spec.matrix.org/latest/client-server-api/)
- [targets/microvms/openclaw.nix](../../targets/microvms/openclaw.nix)
- [Set up Matrix Synapse MicroVM](setup-matrix-microvm.md)
