# Secrets Setup and Management Guide

Complete guide for setting up and managing secrets for the Matrix + OpenClaw microvms.

## Quick Start

### 1. Create 1Password Items

Create manually in 1Password (each field has detailed notes in the item):
- **Vault**: Homelab
- **Matrix Synapse**: Fields documented below
- **OpenClaw**: Fields documented below

### 2. Rotate to Real Secrets

**Required before first use:**

1. **Zen API Key**: Get from your OpenCode Zen provider
   ```bash
   op item edit "OpenClaw" --vault Homelab \
     "zen-api-key=zen_YOUR_REAL_KEY_HERE"
   ```

2. **Matrix Access Token**: Generated after Matrix starts
   ```bash
   # See detailed steps in "Obtaining Matrix Access Token" section below
   ```

3. **(Optional) Passwords**: Change if desired
   ```bash
   op item edit "Matrix Synapse" --vault Homelab \
     "admin-password=$(openssl rand -base64 24 | tr -d '=+/')"
   op item edit "Matrix Synapse" --vault Homelab \
     "openclaw-password=$(openssl rand -base64 24 | tr -d '=+/')"
   ```

### 3. Create Service Account

```bash
# Create service account with access to Homelab vault
op service-account create "MicroVM Secrets" --vault Homelab

# Copy the token (starts with ops_)
# Place on each microvm at: /etc/opnix-token
```

## Matrix Synapse Secrets

**Item**: `op://Homelab/Matrix Synapse/`

### signing-key

**Purpose**: Ed25519 signing key for Matrix federation  
**Format**: `ed25519 <key_id> <64-hex-chars>`  
**Location**: Written to `/var/lib/matrix-synapse/matrix.local.signing.key`

**Regeneration**:
```bash
# Option 1: Let Synapse auto-generate (delete value, restart)
# Option 2: Manual
echo "ed25519 a_auto $(openssl rand -hex 32)"
# Option 3: Synapse tool
generate_signing_key -o signing.key && cat signing.key
```

**Notes**:
- Auto-generated on first start if file doesn't exist
- Keep secret - used for signing federation events
- 64 hex characters exactly for key portion

---

### registration-shared-secret

**Purpose**: Shared secret for admin user registration  
**Format**: Any high-entropy string  
**Location**: Written to `/var/lib/matrix-synapse/registration_secret`

**Regeneration**:
```bash
openssl rand -base64 32
```

**Notes**:
- Only needed for initial user creation
- Used by `matrix-synapse-create-admin` service
- Can be removed after setup if desired

---

### admin-password

**Purpose**: Password for @admin:matrix.local  
**Format**: Strong alphanumeric password  
**Usage**: Directly by user creation script

**Regeneration**:
```bash
openssl rand -base64 24 | tr -d '=+/'
# or
pwgen -s 32 1
```

**Where Used**:
- Login to Element Web: http://matrix
- Username: @admin:matrix.local

**Notes**:
- Save securely - needed for first login
- Can change later via Element settings
- Independent of other secrets

---

### openclaw-password

**Purpose**: Password for @openclaw:matrix.local bot  
**Format**: Strong alphanumeric password  
**Usage**: User creation, then token acquisition

**Regeneration**:
```bash
openssl rand -base64 24 | tr -d '=+/'
```

**Where Used**:
1. User creation (automatic via systemd)
2. Token acquisition (one-time)

**Important**: If you change this, you must also update the access token!

---

## OpenClaw Secrets

**Item**: `op://Homelab/OpenClaw/`

### zen-api-key

**Purpose**: API key for OpenCode Zen provider  
**Format**: `zen_<64-hex>_<32-hex>`  
**Location**: Composed into `/run/openclaw/generated-env`

**Obtaining**:
```
Contact your OpenCode Zen provider for API access
They will provide the key in format: zen_...
Cannot be self-generated
```

**Rotation**:
```bash
op item edit "OpenClaw" --vault Homelab \
  "zen-api-key=zen_YOUR_NEW_KEY"
```

**Notes**:
- Provides access to Zen account and quota
- Keep extremely secret
- Rate limits apply per provider

---

### matrix-access-token

**Purpose**: Access token for Matrix bot authentication  
**Format**: Matrix token (starts with `syt_`)  
**Location**: Composed into `/run/openclaw/generated-env`

## Obtaining Matrix Access Token

This is a **one-time setup process** after Matrix is running:

### Step 1: Start Matrix MicroVM

```bash
nix run .#microvm.nixosConfigurations.matrix.config.microvm.declarationRunner --impure
```

Wait for services to start and users to be created.

### Step 2: Get Bot Password

```bash
op item get "Matrix Synapse" --vault Homelab \
  --field openclaw-password --reveal
```

### Step 3: Login and Get Token

```bash
curl -X POST http://matrix:8008/_matrix/client/r0/login \
  -H "Content-Type: application/json" \
  -d '{
    "type": "m.login.password",
    "user": "openclaw",
    "password": "<password-from-step-2>"
  }'
```

Expected response:
```json
{
  "user_id": "@openclaw:matrix.local",
  "access_token": "syt_abc123def456...",
  "home_server": "matrix.local",
  "device_id": "..."
}
```

### Step 4: Save Token

```bash
op item edit "OpenClaw" --vault Homelab \
  "matrix-access-token=syt_abc123def456..."
```

### Step 5: Restart OpenClaw

The token will be picked up automatically, or restart the microvm:
```bash
# On OpenClaw microvm
sudo systemctl restart openclaw-gateway
```

---

## Architecture

### Individual Secret Storage

```
1Password Vault (Homelab)
├── Matrix Synapse/
│   ├── signing-key                    → /var/lib/matrix-synapse/
│   ├── registration-shared-secret     → /var/lib/matrix-synapse/
│   ├── admin-password                 → used by script
│   └── openclaw-password              → used by script
│
└── OpenClaw/
    ├── zen-api-key                    → composed into env
    └── matrix-access-token            → composed into env
```

### Runtime Composition

**Matrix MicroVM**:
- Opnix syncs secrets to `/run/secrets/matrix-*`
- `matrix-synapse-create-admin` service reads them directly
- No environment file stored

**OpenClaw MicroVM**:
- Opnix syncs secrets to `/run/secrets/openclaw-*`
- `openclaw-generate-env` service composes them:
  ```bash
  echo "OPENCLAW_MATRIX_ACCESS_TOKEN=$TOKEN" > /run/openclaw/generated-env
  echo "ZEN_API_KEY=$ZEN" >> /run/openclaw/generated-env
  ```
- `openclaw-gateway` uses generated file

### Benefits

1. **No duplication**: Each secret stored once
2. **Independent rotation**: Change one without affecting others
3. **Clear dependencies**: Easy to track usage
4. **No stale data**: Always current values
5. **Better audit**: Track specific secret rotation

---

## Service Account Setup

### Creating Service Account

```bash
# In 1Password web UI or CLI
op service-account create "MicroVM Secrets" \
  --vault Homelab \
  --description "For Opnix secrets sync on microvms"

# Copy the token (format: ops_...)
```

### Placing Token on MicroVMs

**Matrix MicroVM**:
```bash
ssh root@matrix
echo "ops_your_token_here" | sudo tee /etc/opnix-token
sudo chmod 600 /etc/opnix-token
```

**OpenClaw MicroVM**:
```bash
ssh root@openclaw
echo "ops_your_token_here" | sudo tee /etc/opnix-token
sudo chmod 600 /etc/opnix-token
```

⚠️ **NEVER commit this token to git!**

---

## Rotation Procedures

### Regular Rotation (every 90 days)

**Signing Key**:
```bash
KEY=$(openssl rand -hex 32)
op item edit "Matrix Synapse" --vault Homelab \
  "signing-key=ed25519 a_auto $KEY"
# Restart Matrix microvm
```

**Passwords**:
```bash
# Admin
op item edit "Matrix Synapse" --vault Homelab \
  "admin-password=$(openssl rand -base64 24 | tr -d '=+/')"

# Bot (requires token update too!)
op item edit "Matrix Synapse" --vault Homelab \
  "openclaw-password=$(openssl rand -base64 24 | tr -d '=+/')"
# Then obtain new access token and update OpenClaw item
```

**Zen API Key**:
```bash
# Get new key from provider
op item edit "OpenClaw" --vault Homelab \
  "zen-api-key=zen_YOUR_NEW_KEY"
```

### Compromise Response

If any secret is compromised:

1. **Immediately rotate the compromised secret**
2. **Check logs** for unauthorized access:
   ```bash
   journalctl -u matrix-synapse -f
   journalctl -u openclaw-gateway -f
   ```
3. **Rotate service account token** if suspected:
   ```bash
   # Delete old service account
   op service-account delete "MicroVM Secrets"
   # Create new one
   op service-account create "MicroVM Secrets" --vault Homelab
   # Update /etc/opnix-token on all microvms
   ```
4. **Review 1Password audit logs**

---

## Troubleshooting

### Secret Not Syncing

```bash
# Check Opnix service
sudo systemctl status onepassword-secrets
sudo journalctl -u onepassword-secrets -f

# Check if secret file exists
ls -la /run/secrets/
cat /run/secrets/matrix-admin-password

# Verify token file
cat /etc/opnix-token  # Should show ops_...
```

### Environment File Not Generated

```bash
# Check generator service
sudo systemctl status openclaw-generate-env
sudo journalctl -u openclaw-generate-env -f

# Check generated file
ls -la /run/openclaw/
cat /run/openclaw/generated-env
```

### Invalid Key Format

If Synapse fails with "Invalid signing key":
- Verify format: `ed25519 <id> <64-hex-chars>`
- No spaces or newlines in the value
- Exactly 64 hex characters for the key

### Cannot Login

- Verify passwords in 1Password match what's on disk
- Check `matrix-synapse-create-admin` service logs
- Ensure users were created: `synapse_admin list_users`

---

## Security Best Practices

1. **Never commit secrets to git**
2. **Rotate regularly** (90 days recommended)
3. **Use unique secrets per environment**
4. **Monitor 1Password audit logs**
5. **Limit service account scope** (only Homelab vault)
6. **Strong passwords** (24+ chars, mixed case, symbols)
7. **Secure token storage** (/etc/opnix-token, 600 perms)
8. **Review access regularly**

---

## Files Reference

- `targets/microvms/matrix.nix` - Matrix microvm configuration
- `targets/microvms/openclaw.nix` - OpenClaw microvm configuration
- `modules/services/openclaw/default.nix` - OpenClaw service module

## See Also

- [1Password CLI Docs](https://developer.1password.com/docs/cli/)
- [Opnix Documentation](https://github.com/brizzbuzz/opnix)
- [Matrix Synapse Docs](https://element-hq.github.io/synapse/latest/)
- [OpenClaw Documentation](https://docs.openclaw.ai)
