# Integrate devenv with Local Caddy

This guide shows how to configure your devenv to automatically add and remove routes to the personal Caddy reverse proxy when entering and exiting the environment.

## Overview

When you `devenv shell` into a project, a helper script can POST your service's route to Caddy's admin API. When you exit, it cleans up by DELETEing the route — no manual Caddy config changes needed.

## Setup

### 1. Create a Caddy Helper Function

Add this to your `devenv.nix`:

```nix
{pkgs, ...}:

let
  # Helper to post a route to Caddy's admin API
  caddyHelper = pkgs.writeShellScript "caddy-route-helper" ''
    #!/bin/bash
    # Usage:
    #   caddy_add_route <hostname> <upstream> [route_id]
    #   caddy_remove_route [route_id]
    
    caddy_add_route() {
      local hostname="$1"
      local upstream="$2"
      local route_id="''${3:-$hostname}"
      
      echo "[devenv] Adding Caddy route: $hostname -> $upstream"
      curl -s -X POST http://localhost:2019/config/apps/http/servers/srv0/routes \
        -H "Content-Type: application/json" \
        -d "{
          \"@id\": \"$route_id\",
          \"match\": [{\"host\": [\"$hostname\"]}],
          \"handle\": [{
            \"handler\": \"reverse_proxy\",
            \"upstreams\": [{\"dial\": \"$upstream\"}]
          }]
        }" || echo "[devenv] WARNING: Failed to add Caddy route"
    }
    
    caddy_remove_route() {
      local route_id="''${1}"
      if [ -z "$route_id" ]; then
        echo "[devenv] ERROR: route_id required for removal"
        return 1
      fi
      echo "[devenv] Removing Caddy route: $route_id"
      # Try to find and delete the route by ID
      curl -s http://localhost:2019/config/apps/http/servers/srv0/routes \
        | jq -r ".[] | select(.\"@id\" == \"$route_id\") | @base64d" > /dev/null
      # For simplicity, find the route index and delete
      local index=$(curl -s http://localhost:2019/config/apps/http/servers/srv0/routes \
        | jq "map(select(.\"@id\" == \"$route_id\")) | length")
      if [ "$index" -gt 0 ]; then
        curl -s -X DELETE http://localhost:2019/config/apps/http/servers/srv0/routes/0 || echo "[devenv] WARNING: Failed to remove Caddy route"
      fi
    }
  '';
in

{
  # Your other devenv config
  
  enterShell = ''
    # Load Caddy helpers
    source ${caddyHelper}
    
    # Add your service route to Caddy
    # Example: caddy_add_route "myapp.localhost" "localhost:3000"
    
    echo "✓ Development environment ready"
  '';
  
  exitShell = ''
    # Remove your service route from Caddy on exit (optional)
    # Example: caddy_remove_route "myapp.localhost"
  '';
}
```

### 2. Enable Caddy in Your System Config

Ensure `myConfig.caddy.enable = true` in your Nix configuration:

```nix
{
  config.myConfig.caddy = {
    enable = true;
    port = 80;
  };
}
```

Apply the configuration:

```bash
darwin-rebuild switch --flake .
```

### 3. Test the Integration

Create a simple devenv project:

```bash
mkdir -p ~/test-project
cd ~/test-project
```

Create a simple `devenv.nix`:

```nix
{pkgs, ...}: {
  enterShell = ''
    echo "=== Test Project ==="
    echo "Adding Caddy route..."
    curl -s -X POST http://localhost:2019/config/apps/http/servers/srv0/routes \
      -H "Content-Type: application/json" \
      -d '{
        "@id": "test-project",
        "match": [{"host": ["test.localhost"]}],
        "handle": [{
          "handler": "reverse_proxy",
          "upstreams": [{"dial": "localhost:8000"}]
        }]
      }'
    echo ""
    echo "✓ Route added! Try: curl http://test.localhost"
  '';
  
  exitShell = ''
    echo ""
    echo "Cleaning up Caddy route..."
    curl -s -X DELETE http://localhost:2019/config/apps/http/servers/srv0/routes/0 || true
  '';
}
```

Enter devenv:

```bash
devenv shell
# Should see: Route added!
```

Verify the route exists:

```bash
# From another terminal:
curl -s http://localhost:2019/config/apps/http/servers/srv0/routes | jq .
```

Exit devenv:

```bash
exit
# Should see: Cleaning up Caddy route...
```

## Advanced: Persistent Routes

If you want routes to persist across sessions (not cleaned up on exit), add them to your Nix config instead:

```nix
{
  config.myConfig.caddy.hosts = {
    "myservice.localhost" = "localhost:8000";
  };
}
```

Then rebuild the system — the route becomes part of Caddy's base configuration.

## Troubleshooting

### "curl: (7) Failed to connect"

Caddy's admin API is not responding. Check:

```bash
ps aux | grep caddy
# Should show a running Caddy process

launchctl list | grep caddy
# Should show org.nixos.caddy is loaded
```

### Route not appearing after POST

Check that the `content-type` header is set to `application/json` and the JSON is valid:

```bash
curl -v -X POST http://localhost:2019/config/apps/http/servers/srv0/routes \
  -H "Content-Type: application/json" \
  -d '{
    "@id": "test",
    "match": [{"host": ["test.localhost"]}],
    "handle": [{
      "handler": "reverse_proxy",
      "upstreams": [{"dial": "localhost:9000"}]
    }]
  }'
```

Review the response for errors.

### DNS not resolving

Verify dnsmasq is running:

```bash
launchctl list | grep dnsmasq
# Should show org.nixos.dnsmasq is loaded

dig +short test.localhost @127.0.0.1 -p 5353
# Should return 127.0.0.1
```

## See Also

- [Add a Local Dev DNS Name](add-local-dev-dns-name.md) — Static configuration approach
- [devenv Documentation](https://devenv.sh)
- [Caddy Admin API Reference](https://caddyserver.com/docs/api)
