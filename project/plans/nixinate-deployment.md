# Nixinate Deployment Implementation

This document shows how to implement nixinate-style deployment for the nix repo.

## Overview

Nixinate provides a simple `nix run .#apps.nixinate.<host>` interface for deploying to existing NixOS machines. This complements nixos-anywhere (initial install) with a streamlined update workflow.

## Implementation Steps

### 1. Add nixinate input to flake.nix

```nix
{
  inputs = {
    # ... existing inputs ...
    
    nixinate = {
      url = "github:MatthewCroughan/nixinate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  
  outputs = { self, nixpkgs, nixinate, ... } @ inputs:
    let
      # ... existing helpers ...
    in {
      # Add nixinate apps for all supported systems
      apps = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"] (system:
        nixinate.nixinate.${system} self
      );
      
      # ... rest of outputs ...
    };
}
```

### 2. Add nixinate configuration to each target

For **existing artisanal machines** (zero, etc.):

```nix
# targets/zero/default.nix
{ config, pkgs, ... }:

{
  # Existing configuration...
  
  # Add nixinate deployment config
  _module.args.nixinate = {
    host = "zero.local";  # Or IP address
    sshUser = "monkey";
    buildOn = "remote";   # Build on the target machine
    substituteOnTarget = true;  # Use target's binary cache
  };
}
```

For **disposable machine types** (type-server, type-desktop):

```nix
# machine-types/server.nix
{ config, lib, ... }:

{
  # ... existing config ...
  
  # Note: For disposable machines, you'd set this per-deployment
  # via a local override or DHCP-assigned hostname
}
```

### 3. Create per-machine deployment configs

For machines without hardcoded hostnames (disposable pattern), create deployment configs:

```nix
# deployments/homelab-server.nix
{
  # Extends type-server for a specific deployment
  _module.args.nixinate = {
    host = "192.168.1.50";
    sshUser = "monkey";
    buildOn = "remote";
  };
}
```

### 4. Add helper script

Create `scripts/deploy.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

DEPLOYMENT="${1:-}"

if [ -z "$DEPLOYMENT" ]; then
  echo "Usage: $0 <hostname>"
  echo ""
  echo "Available deployments:"
  nix flake show --json 2>/dev/null | \
    jq -r '.apps["x86_64-linux"]? | keys[]? | select(startswith("nixinate.")) | sub("^nixinate\\."; "  - ")' \
    2>/dev/null || echo "  (run 'nix flake show' to see available deployments)"
  exit 1
fi

echo "🚀 Deploying to $DEPLOYMENT..."
nix run ".#apps.nixinate.$DEPLOYMENT"
```

### 5. Update devenv.nix with deploy task

```nix
# In devenv.nix tasks section
"deploy" = {
  description = "Deploy to a remote NixOS machine";
  exec = ''
    if [ -z "''${1:-}" ]; then
      echo "Usage: devenv tasks run deploy -- <hostname>"
      exit 1
    fi
    nix run ".#apps.nixinate.$1"
  '';
};
```

## Usage Examples

```bash
# Deploy to zero
nix run .#apps.nixinate.zero

# Deploy to a disposable server
nix run .#apps.nixinate.homelab-server

# Or with the helper
devenv tasks run deploy -- zero
```

## Comparison: Current vs Nixinate

| Aspect | Current | With Nixinate |
|--------|---------|---------------|
| **Initial install** | `nixos-anywhere` | `nixos-anywhere` (unchanged) |
| **Update command** | SSH + `nixos-rebuild` | `nix run .#apps.nixinate.<host>` |
| **Build location** | Always remote | Configurable (local/remote) |
| **SSH keys** | Manual setup | Uses standard SSH |
| **Rollback** | Manual on host | Not included (use `nixos-rebuild switch --rollback` via SSH) |
| **Multi-host** | Script loops | One command per host |

## Benefits for This Repo

1. **Simpler updates**: One command instead of SSH + rebuild
2. **Local builds optional**: Build locally and copy closure for slow remote machines
3. **Consistent interface**: Same pattern for all machines
4. **Works with disposable**: Can deploy to type-* machines with per-deployment config

## Limitations

- No built-in rollback command (still need SSH for that)
- No parallel multi-host deployment
- Requires SSH access configured

## Alternative: Custom Implementation

If you prefer not to add a dependency, you could create a custom deployment script:

```nix
# modules/deploy.nix
{ config, pkgs, lib, ... }:

let
  mkDeployApp = name: deploymentConfig:
    let
      host = deploymentConfig.host;
      user = deploymentConfig.sshUser or "root";
      buildOn = deploymentConfig.buildOn or "remote";
    in
    pkgs.writeShellScriptBin "deploy-${name}" ''
      set -euo pipefail
      echo "🚀 Deploying ${name} to ${host}..."
      
      ${if buildOn == "remote" then ''
        # Copy flake to remote and build there
        echo "📤 Copying flake to ${host}..."
        nix copy --to "ssh://${user}@${host}" ${self}
        
        echo "🔨 Building on ${host}..."
        ssh ${user}@${host} "sudo nixos-rebuild switch --flake ${self}#${name}"
      '' else ''
        # Build locally and copy closure
        echo "🔨 Building locally..."
        nix build ${self}#nixosConfigurations.${name}.config.system.build.toplevel
        
        echo "📤 Copying closure to ${host}..."
        nix copy --to "ssh://${user}@${host}" ./result
        
        echo "🎯 Activating on ${host}..."
        ssh ${user}@${host} "sudo ./result/bin/switch-to-configuration switch"
      ''}
      
      echo "✅ Deployment complete!"
    '';
in
{
  # Generate apps from deployment configs
}
```

## Recommendation

For this repository, **nixinate is a good fit** because:

1. ✅ You already use flakes properly
2. ✅ You have standard SSH access to machines
3. ✅ You want simple, one-command deployments
4. ✅ It complements nixos-anywhere well (install vs update)

Start with the disposable machines (type-server, type-desktop) since they don't have per-machine configs, then add artisanal machines as needed.
