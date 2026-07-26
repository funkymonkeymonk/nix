# Cloud-init Format

Reference for the cloud-init YAML file used to configure new machines before applying a full Nix flake target.

## Host-level Cloud-init

**Location:** `/etc/cloud-init.yaml`

Defines system-wide bootstrap configuration.

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `hostname` | string | Host system hostname |
| `timezone` | string | System timezone (e.g. `America/New_York`) |
| `locale` | string | System locale (e.g. `en_US.UTF-8`) |
| `ssh_authorized_keys` | list | SSH keys for root access |
| `nix.target` | string | Nix flake target name |
| `nix.branch` | string | Git branch for flake |
| `nix.impure` | bool | Enable impure evaluation |
| `nix.roles` | list | Enabled Nix roles |

## CLI Commands

Manage cloud-init via `nix-cloud-init`:

```bash
nix-cloud-init show
sudo nix-cloud-init init
sudo nix-cloud-init set hostname myserver
sudo nix-cloud-init set target type-server
sudo nix-cloud-init validate
sudo nix-cloud-init edit
```

See `nix-cloud-init help` for the full command reference.
