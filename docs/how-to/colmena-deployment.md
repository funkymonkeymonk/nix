# Colmena Deployment Guide

This repository uses [Colmena](https://colmena.cli.rs/) for deploying NixOS configurations to remote hosts.

## Overview

Colmena is a simple, stateless NixOS deployment tool that:
- Deploys to multiple hosts in parallel
- Supports tag-based filtering
- Manages secrets out-of-band (not in Nix store)
- Has zero state (no database to manage)

## Quick Start

### 1. Install Colmena

Colmena is available in nixpkgs:

```bash
nix-shell -p colmena
```

Or add to your system packages.

### 2. Configure Your Hosts

Edit `flake.nix` and uncomment/modify the example host configurations in the `colmenaHive` output. For each host, specify:

- `deployment.targetHost` - SSH hostname or IP
- `deployment.targetUser` - SSH user (default: root)
- `deployment.tags` - Tags for grouping (`--on @tag`)
- `deployment.buildOnTarget` - Build remotely vs locally

### 3. Deploy

```bash
# Show all available nodes
colmena eval -E '{ nodes }: builtins.attrNames nodes'

# Build all configurations (no deployment)
colmena build

# Deploy to all nodes (requires --on since allowApplyAll = false)
colmena apply --on @servers

# Deploy to specific node
colmena apply --on server-01

# Deploy to multiple nodes by name
colmena apply --on server-01,server-02

# Deploy to nodes matching pattern
colmena apply --on 'server-*'

# Deploy with verbose output
colmena apply --on server-01 -v

# Build on target instead of locally
colmena apply --on server-01 --build-on-target
```

## Deployment Commands

| Command | Description |
|---------|-------------|
| `colmena build` | Build all configurations locally |
| `colmena apply` | Build and deploy to remote hosts |
| `colmena apply --on @tag` | Deploy to tagged hosts |
| `colmena apply --on host1,host2` | Deploy to specific hosts |
| `colmena upload-keys` | Upload secrets to hosts |
| `colmena exec --on @servers -- COMMAND` | Run command on hosts |
| `colmena repl` | Interactive REPL with all configs |

## Deployment Goals

Control what happens during deployment:

```bash
colmena apply build        # Build only
colmena apply push         # Copy closures only
colmena apply switch       # Activate and make boot default (default)
colmena apply boot         # Make boot default only
colmena apply test         # Activate but don't make boot default
colmena apply dry-activate # Show what would change
colmena apply --reboot     # Reboot after activation
```

## Adding a New Host

1. **Add the host configuration** to `flake.nix` in the `colmenaHive` section:

```nix
my-server = { name, ... }: {
  deployment = {
    targetHost = "my-server.example.com";
    targetUser = "monkey";
    tags = [ "server" "prod" ];
    buildOnTarget = true;
  };
  
  # Host configuration
  imports = [ ./machine-types/server.nix ];
  networking.hostName = "my-server";
  
  # Host-specific overrides
  services.my-service.enable = true;
};
```

2. **Ensure SSH access** - The target user must have SSH key auth (password auth won't work)

3. **Test connectivity**:

```bash
colmena exec --on my-server -- echo "Hello from $(hostname)"
```

4. **Deploy**:

```bash
colmena apply --on my-server
```

## Secret Management

Colmena can deploy secrets out-of-band (never touches Nix store):

```nix
my-server = { ... }: {
  deployment.keys.my-secret = {
    # One of: text, keyFile, or keyCommand
    text = "super-secret-value";
    # keyFile = /path/to/secret;
    # keyCommand = [ "pass" "show" "my-secret" ];
    
    destDir = "/run/keys";
    user = "myapp";
    permissions = "0600";
    uploadAt = "pre-activation";  # or "post-activation"
  };
  
  # Use the secret in your service
  systemd.services.my-service = {
    serviceConfig.LoadCredential = "secret:/run/keys/my-secret";
  };
};
```

Upload secrets without full deployment:

```bash
colmena upload-keys --on my-server
```

## Tags and Filtering

Use tags to organize hosts:

```nix
web-01 = {
  deployment.tags = [ "web" "prod" "us-east" ];
  ...
};

web-02 = {
  deployment.tags = [ "web" "prod" "us-west" ];
  ...
};

db-01 = {
  deployment.tags = [ "db" "prod" ];
  ...
};
```

Deploy using tags:

```bash
# All production hosts
colmena apply --on @prod

# All web servers
colmena apply --on @web

# Multiple tags (OR logic)
colmena apply --on @web,@db

# Combine tags and names
colmena apply --on @prod,web-01

# Pattern matching
colmena apply --on 'web-*'
colmena apply --on '@*-east'
```

## Parallelism

Control deployment parallelism:

```bash
# Deploy 5 hosts at a time (default: 10)
colmena apply --on @servers -p 5

# Unlimited parallelism
colmena apply --on @servers -p 0

# Sequential deployment
colmena apply --on @servers -p 1
```

## Local Deployment

Apply configuration to the local machine:

```bash
colmena apply-local
```

Useful for testing configurations before pushing to remote hosts.

## Troubleshooting

### SSH Connection Issues

Ensure SSH keys are set up:

```bash
ssh-copy-id user@hostname
```

Use `SSH_CONFIG_FILE` for complex SSH setups:

```bash
SSH_CONFIG_FILE=~/.ssh/config.colmena colmena apply --on my-server
```

### Build Failures

Build on target to avoid copying large closures:

```nix
deployment.buildOnTarget = true;
```

Or use command-line flag:

```bash
colmena apply --on my-server --build-on-target
```

### Unknown Profile Warnings

Colmena warns if remote has a profile not in local store. To force deployment:

```bash
colmena apply --on my-server --force-replace-unknown-profiles
```

Or set per-node:

```nix
deployment.replaceUnknownProfiles = true;
```

### Evaluation Errors

Show full trace:

```bash
colmena apply --on my-server --show-trace
```

Use verbose mode:

```bash
colmena apply --on my-server -v
```

## Best Practices

1. **Always use `--on`** - Set `allowApplyAll = false` in meta to prevent accidental full-cluster deployment

2. **Tag your hosts** - Makes it easy to deploy to groups (`@prod`, `@staging`, `@web`)

3. **Test locally first** - Use `colmena apply-local` to test before remote deployment

4. **Use dry-activate** - Preview changes: `colmena apply dry-activate --on my-server`

5. **Build on target for large configs** - Set `deployment.buildOnTarget = true` for hosts with more resources

6. **Keep secrets out of store** - Use `deployment.keys` for sensitive data

7. **Use GC roots** - Add `--keep-result` to prevent garbage collection during deployment

## Example Workflow

```bash
# 1. Make changes to configuration
vim flake.nix

# 2. Build to check for errors
colmena build

# 3. Test on one host
colmena apply dry-activate --on server-01
colmena apply --on server-01

# 4. Roll out to staging
colmena apply --on @staging

# 5. Roll out to production
colmena apply --on @prod
```

## Further Reading

- [Colmena Manual](https://colmena.cli.rs/)
- [Colmena GitHub](https://github.com/zhaofengli/colmena)
- [Matrix Chat](https://matrix.to/#/#colmena:nixos.org)
