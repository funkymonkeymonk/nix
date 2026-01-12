# OpNix: 1Password Integration for NixOS

OpNix provides seamless 1Password integration for NixOS systems, enabling secure secret management without storing secrets in your Nix configuration.

## Overview

OpNix fetches secrets from 1Password at system boot time and caches them in `/run/opnix/secrets/` (a temporary filesystem that doesn't persist after reboot). Services can then read these secrets at startup without hardcoding sensitive values.

## Components

### 1. OnePassword Secrets Service (`onepassword-secrets.nix`)
- **Purpose**: Systemd service that fetches secrets from 1Password using a service account token
- **Location**: `/run/opnix/secrets/`
- **Security**: Secrets stored in tmpfs, never written to persistent storage

### 2. Service Account Authentication
- **Token Location**: `/etc/opnix-token`
- **Permissions**: `root:root 0600`
- **Scope**: Read-only access to specified vault items

### 3. Task Automation
- Setup, validation, and token rotation commands
- Integrated with existing Nix development workflow

## Quick Setup

### Prerequisites
1. **1Password Account**: With access to the Homelab vault
2. **1Password CLI**: Installed and authenticated
3. **Service Account Permissions**: Ability to create service accounts (or have admin create one)

### Initial Setup

1. **Set up 1Password CLI (if not already done)**:
   ```bash
   task 1password:setup
   ```

2. **Generate and configure service account**:
   ```bash
   task 1password:service:setup
   ```

3. **Validate the setup**:
   ```bash
   task 1password:service:validate
   ```

4. **Rebuild the system**:
   ```bash
   task switch:nixos
   ```

### Manual Service Account Creation (if automated setup fails)

If the automated service account creation doesn't work (due to permissions), create it manually:

1. **In 1Password Desktop/Web**:
   - Go to Settings → Developers → Service Accounts
   - Create new service account named `nixos-<hostname>`
   - Grant read access to the Homelab vault
   - Save the token securely

2. **Store the token on the system**:
   ```bash
   # As root, create the token file with proper permissions
   sudo touch /etc/opnix-token
   sudo chmod 600 /etc/opnix-token
   sudo chown root:root /etc/opnix-token
   
   # Paste your service account token
   sudo nano /etc/opnix-token
   ```

3. **Validate the setup**:
   ```bash
   task 1password:service:validate
   ```

## Configuration

### Service Module Configuration

```nix
services.onepassword-secrets = {
  enable = true;
  tokenFile = "/etc/opnix-token";
  vault = "Homelab";
  secrets = {
    serviceName = {
      reference = "op://vault/item/field";
      owner = "service-user";
      services = ["service-name"];
      permissions = "0600";
    };
  };
};
```

### Example: Linkwarden Configuration

```nix
services = {
  onepassword-secrets = {
    enable = true;
    vault = "Homelab";
    secrets = {
      linkwardenDbPassword = {
        reference = "op://Homelab/Linkwarden Database Password/password";
        owner = "linkwarden";
        services = ["linkwarden"];
      };
      nextauthSecret = {
        reference = "op://Homelab/Linkwarden NextAuth Secret/password";
        owner = "linkwarden";
        services = ["linkwarden"];
      };
    };
  };
  
  linkwarden = {
    enable = true;
    port = 3000;
  };
};
```

## Usage in Services

### Reading Secrets

Services can read secrets at runtime using `$(cat /path/to/secret)`:

```nix
systemd.services.your-service = {
  environment = {
    SECRET_VALUE = "$(cat /run/opnix/secrets/yourSecret)";
  };
};
```

### Service Dependencies

The OpNix module automatically sets up service dependencies:

```nix
systemd.services.your-service = {
  after = ["onepassword-secrets.service"];
  wants = ["onepassword-secrets.service"];
};
```

## Task Commands

### Service Account Management

- **`task 1password:service:setup`** - Complete first-time setup
- **`task 1password:service:generate-token`** - Generate new service account token
- **`task 1password:service:validate`** - Validate token and secret access
- **`task 1password:service:rotate`** - Rotate existing token

### 1Password CLI

- **`task 1password:setup`** - Set up 1Password CLI authentication

## Security Considerations

### Token Security
- Service account token stored in `/etc/opnix-token` with `600` permissions
- Root-owned file, only readable by root user
- Token grants minimal permissions (read-only to specific vault)

### Runtime Security
- Secrets cached in `/run/opnix/secrets/` (tmpfs)
- Individual secret files with per-service ownership and permissions
- Automatic cleanup on service stop

### Best Practices
1. **Principle of Least Privilege**: Service accounts only have read access to needed vaults
2. **Regular Rotation**: Rotate service account tokens periodically
3. **Audit Trail**: Service account activity logged in 1Password
4. **Backup Planning**: Have manual secret access as backup

## Troubleshooting

### Common Issues

#### Service Not Starting
```bash
# Check service status
systemctl status onepassword-secrets.service

# Check logs
journalctl -u onepassword-secrets.service
```

#### Token Authentication Failed
```bash
# Validate token setup
task 1password:service:validate

# Regenerate token if needed
task 1password:service:rotate
```

#### Secret Not Accessible
```bash
# Check secret file exists
ls -la /run/opnix/secrets/

# Check permissions
stat /run/opnix/secrets/secretName

# Test manual secret access
export OP_SERVICE_ACCOUNT_TOKEN=$(cat /etc/opnix-token)
op read "op://vault/item/field"
```

#### PostgreSQL Password Issues
```bash
# Check password setting service
systemctl status set-postgres-passwords.service

# Verify database connection
sudo -u postgres psql -c "\du"
```

### Debug Mode

For detailed debugging, temporarily modify the service to include verbose logging:

```bash
# Edit the service to add debug output
sudo systemctl edit onepassword-secrets.service

# Add to [Service] section:
# ExecStartPre=/usr/bin/echo "Debug: Starting secret fetch"
# ExecStartPost=/usr/bin/echo "Debug: Secret fetch completed"

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart onepassword-secrets.service
```

## Migration from Hardcoded Secrets

### Before (Hardcoded)
```nix
services.linkwarden = {
  environment = {
    NEXTAUTH_SECRET = "hardcoded-secret-here";
    DATABASE_URL = "postgresql://user:password@localhost/db";
  };
};
```

### After (OpNix)
```nix
services = {
  onepassword-secrets = {
    enable = true;
    secrets = {
      nextauthSecret = {
        reference = "op://Homelab/Linkwarden NextAuth Secret/password";
        owner = "linkwarden";
        services = ["linkwarden"];
      };
    };
  };
  
  linkwarden = {
    environment = {
      NEXTAUTH_SECRET = "$(cat /run/opnix/secrets/nextauthSecret)";
      DATABASE_URL = "postgresql://user:$(cat /run/opnix/secrets/dbPassword)@localhost/db";
    };
  };
};
```

## Backup and Recovery

### Service Account Backup
Store service account configuration securely (encrypted backup, secure password manager):

1. **Service account name and purpose**
2. **Vault permissions granted**
3. **Token (if you need to restore, though better to regenerate)**

### Manual Secret Access
If OpNix fails, you can manually set secrets:

```bash
# Emergency manual secret setting
sudo mkdir -p /run/opnix/secrets
echo "your-secret-value" | sudo tee /run/opnix/secrets/secretName
sudo chmod 600 /run/opnix/secrets/secretName
sudo chown service-user:service-group /run/opnix/secrets/secretName
```

## Integration with CI/CD

### GitHub Actions
The service account token should be treated as a secret in CI/CD:

```yaml
# .github/workflows/deploy.yml
- name: Deploy to NixOS
  run: |
    echo "${{ secrets.OPNIX_TOKEN }}" | ssh remote-system "sudo tee /etc/opnix-token"
    ssh remote-system "sudo chmod 600 /etc/opnix-token"
    ssh remote-system "sudo nixos-rebuild switch"
```

## Performance Considerations

### Startup Time Impact
- Service account authentication: ~2-3 seconds
- Secret fetching: ~1-2 seconds per secret
- Overall impact: <10 seconds to system boot time

### Resource Usage
- Memory: Minimal (secrets stored as small text files)
- Disk: None (tmpfs storage)
- Network: Only during boot and manual token refresh

## Advanced Usage

### Multiple Vaults
Configure different secrets from different vaults:

```nix
services.onepassword-secrets = {
  # Primary vault configuration
  vault = "Production";
  
  secrets = {
    prodDbPassword = {
      reference = "op://Production/Database/password";
      owner = "postgres";
      services = ["postgresql"];
    };
    
    devDbPassword = {
      reference = "op://Development/Database/password";
      owner = "postgres";
      services = ["postgresql-dev"];
    };
  };
};
```

### Conditional Secret Loading
For environments where some secrets might not be available:

```nix
services.onepassword-secrets.secrets = {
  optionalSecret = lib.mkIf config.services.optionalService.enable {
    reference = "op://Homelab/Optional/secret";
    owner = "optional-service";
    services = ["optional-service"];
  };
};
```

## Support and Contributing

For issues, feature requests, or contributions:

1. **Issues**: Check existing issues or create new ones
2. **Debugging**: Provide logs from `journalctl -u onepassword-secrets.service`
3. **Contributions**: Follow the existing code style and testing patterns

---

*OpNix makes 1Password integration with NixOS secure, reliable, and developer-friendly.*