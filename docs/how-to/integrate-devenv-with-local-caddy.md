---
title: "Integrate devenv with Local Caddy"
description: "Automatically register devenv services with the local Caddy reverse proxy"
type: how-to
---

# Integrate devenv with Local Caddy

This guide shows how to configure your `devenv.nix` to automatically register services with the personal Caddy reverse proxy, making them accessible via `.internal` domains.

## Prerequisites

- Caddy is enabled in your host config: `myConfig.caddy.enable = true`
- Your services listen on localhost ports
- You have curl (included in base role)

## Basic Setup

In your `devenv.nix`, after defining services, register them with Caddy.

### Example 1: Simple Service Registration

```nix
{config, pkgs, lib, ...}:

{
  services.postgres = {
    enable = true;
    port = 5432;
  };

  # After all services are defined, register important ones with Caddy
  tasks.post.setup = {
    exec = ''
      echo "→ Registering services with Caddy..."
      curl -X POST http://localhost:2019/config/apps/http/servers/srv0/routes \
        -H "Content-Type: application/json" \
        -d '{
          "@id": "db-admin",
          "match": [{"host": ["db-admin.internal"]}],
          "handle": [{
            "handler": "reverse_proxy",
            "upstreams": [{"dial": "localhost:5050"}]
          }]
        }' 2>/dev/null || echo "  (Caddy admin API not available)"
    '';
    after = ["services"];
  };
}
```

### Example 2: Web Service Registration

```nix
{config, pkgs, ...}:

{
  services.http = {
    enable = true;
    host = "localhost";
    port = 3000;
  };

  tasks.post.register-services = {
    exec = ''
      echo "→ Registering dev services with Caddy..."

      curl -s -X POST http://localhost:2019/config/apps/http/servers/srv0/routes \
        -H "Content-Type: application/json" \
        -d '{
          "@id": "app",
          "match": [{"host": ["app.internal"]}],
          "handle": [{
            "handler": "reverse_proxy",
            "upstreams": [{"dial": "localhost:3000"}]
          }]
        }' >/dev/null 2>&1 || true

      echo "  → app.internal → localhost:3000"
    '';
    after = ["services"];
  };
}
```

## Dynamic Registration Pattern

For reusable registration, create a helper function:

```nix
{config, pkgs, lib, ...}:

let
  # Helper to register a service with Caddy admin API
  registerWithCaddy = {host, upstream}:
    ''
      curl -s -X POST http://localhost:2019/config/apps/http/servers/srv0/routes \
        -H "Content-Type: application/json" \
        -d '{
          "@id": "${host}",
          "match": [{"host": ["${host}"]}],
          "handle": [{
            "handler": "reverse_proxy",
            "upstreams": [{"dial": "${upstream}"}]
          }]
        }' >/dev/null 2>&1 || true
      echo "  → ${host} → ${upstream}"
    '';

in
{
  services.web = {
    enable = true;
    port = 3000;
  };

  tasks.post.register-services = {
    exec = ''
      echo "→ Registering dev services with Caddy..."
      ${registerWithCaddy {host = "app.internal"; upstream = "localhost:3000";}}
    '';
    after = ["services"];
  };
}
```

## Cleanup on Exit

To remove routes when devenv shuts down, use a cleanup hook:

```nix
{config, pkgs, ...}:

{
  # Your service configuration...

  # Optional: clean up Caddy routes when devenv exits
  tasks.cleanup = {
    exec = ''
      echo "→ Cleaning up Caddy routes..."
      curl -s -X DELETE http://localhost:2019/config/apps/http/servers/srv0/routes/@id/app.internal || true
    '';
  };
}
```

## Verifying Registration

After starting devenv, verify the route is registered:

```bash
# List all registered routes
curl http://localhost:2019/config/apps/http/servers/srv0/routes | jq '.'

# Test the route
curl http://app.internal/
```

## Common Patterns

### Registering Multiple Services

```bash
#!/usr/bin/env bash
# Save as: register-services.sh

register_service() {
  local host=$1
  local upstream=$2

  curl -s -X POST http://localhost:2019/config/apps/http/servers/srv0/routes \
    -H "Content-Type: application/json" \
    -d "{
      \"@id\": \"${host}\",
      \"match\": [{\"host\": [\"${host}\"]}],
      \"handle\": [{
        \"handler\": \"reverse_proxy\",
        \"upstreams\": [{\"dial\": \"${upstream}\"}]
      }]
    }" >/dev/null 2>&1

  echo "Registered: ${host} → ${upstream}"
}

# Register services
register_service "app.internal" "localhost:3000"
register_service "api.internal" "localhost:8000"
register_service "admin.internal" "localhost:9000"
```

Use in devenv:

```nix
tasks.post.register = {
  exec = ''
    ${pkgs.bash}/bin/bash ./register-services.sh
  '';
  after = ["services"];
};
```

## Troubleshooting

### Caddy Admin API Not Responding

```bash
# Check if Caddy is running
launchctl list | grep caddy

# Check logs
tail -f "$HOME/.local/share/caddy/caddy.log"
```

### Routes Disappearing After Reboot

Routes added via the admin API are ephemeral and lost when Caddy restarts. For persistent routes:

1. Add them to your host configuration (see [Add Local Dev DNS Names](add-local-dev-dns-name.md))
2. Or add them in devenv startup if they're development-specific

### Cannot Connect to Service

```bash
# Test if the upstream is reachable
curl http://localhost:3000/

# Check Caddy configuration
curl http://localhost:2019/config/apps/http/servers/srv0/routes | jq '.[] | select(.match[0].host[0] == "app.internal")'
```

### DNS Not Resolving

Verify dnsmasq is running:

```bash
launchctl list | grep dnsmasq
# Should show org.nixos.dnsmasq is loaded

dig +short app.internal @127.0.0.1 -p 5353
# Should return 127.0.0.1
```

## See Also

- [Add Local Dev DNS Names](add-local-dev-dns-name.md)
- [Caddy Admin API](https://caddyserver.com/docs/api)
- [devenv Documentation](https://devenv.sh/)
