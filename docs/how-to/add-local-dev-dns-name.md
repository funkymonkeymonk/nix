---
title: "Add Local Dev DNS Names to Caddy"
description: "Configure static and dynamic DNS routes through the Caddy reverse proxy for local development"
type: how-to
---

# Add Local Dev DNS Names

Caddy (when enabled with `myConfig.caddy.enable = true`) provides a personal reverse proxy for local development with automatic DNS resolution for `.internal` domains.

## Static Routes via Configuration

Static routes are configured in your host configuration and persist across system rebuilds.

### Step 1: Add to `myConfig.caddy.hosts`

In your host file (e.g., `hosts/wweaver/default.nix`):

```nix
myConfig = {
  caddy.enable = true;
  caddy.hosts = {
    "myapp.internal" = "localhost:3000";
    "api.internal" = "localhost:8000";
    "admin.internal" = "localhost:9000";
  };
};
```

### Step 2: Rebuild

```bash
darwin-rebuild switch --flake .#<hostname>
```

### Verify

```bash
curl http://myapp.internal/
```

## Dynamic Routes via Admin API

The Caddy admin API (running on `localhost:2019`) allows you to add routes without rebuilding.

### Query Current Configuration

```bash
curl http://localhost:2019/config/apps/http/servers/srv0/routes
```

### Add a Dynamic Route

```bash
# Add route for a new service
curl -X POST http://localhost:2019/config/apps/http/servers/srv0/routes \
  -H "Content-Type: application/json" \
  -d '{
    "@id": "my-temporary-app",
    "match": [{"host": ["newapp.internal"]}],
    "handle": [{
      "handler": "reverse_proxy",
      "upstreams": [{"dial": "localhost:5000"}]
    }]
  }'
```

### Query a Specific Route

```bash
curl http://localhost:2019/config/apps/http/servers/srv0/routes/@id/my-temporary-app
```

### Delete a Route

If you assigned an `@id`, delete by ID:

```bash
curl -X DELETE http://localhost:2019/config/apps/http/servers/srv0/routes/@id/my-temporary-app
```

Or delete by index:

```bash
curl -X DELETE http://localhost:2019/config/apps/http/servers/srv0/routes/0
```

## DNS Resolution

- **dnsmasq**: Resolves `*.internal` to `127.0.0.1` on port 5353
- **macOS resolver**: `/etc/resolver/internal` points to `127.0.0.1:5353`
- **`localhost`**: The bare `localhost` name resolves to `127.0.0.1` via OS defaults, but it is not used for named services

Verify DNS resolution:

```bash
dig +short myapp.internal @127.0.0.1 -p 5353
# Should return: 127.0.0.1
```

## Health Checks

Caddy exposes a health endpoint:

```bash
curl http://localhost:80/
# Returns: "Caddy running"
```

## Troubleshooting

### DNS Resolution Not Working

Verify dnsmasq is running:

```bash
launchctl list | grep dnsmasq
```

Check resolver configuration:

```bash
cat /etc/resolver/internal
```

### Caddy Not Responding

```bash
launchctl list | grep caddy
# Should show: org.nixos.caddy
```

View logs:

```bash
tail -50 "$HOME/.local/share/caddy/caddy.log"
tail -50 "$HOME/.local/share/caddy/caddy.error.log"
```

### Route Not Working

1. Verify the route is configured:

   ```bash
   curl http://localhost:2019/config/apps/http/servers/srv0/routes | jq .
   ```

2. Check Caddy logs:

   ```bash
   tail -f /tmp/caddy.log
   ```

3. Test the upstream service is running:

   ```bash
   curl http://localhost:3000/
   ```

### Port 80 Permission Denied

Caddy requires elevated privileges to bind to port 80. On macOS with nix-darwin, launchd runs the service with appropriate capabilities. If you see "permission denied", verify:

- Caddy service is running as your user (not root)
- `launchctl list org.nixos.caddy` shows the service is loaded
- No other process is listening on port 80: `lsof -i :80`

## See Also

- [Integrate devenv with Local Caddy](integrate-devenv-with-local-caddy.md)
- [Caddy Reverse Proxy Documentation](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Caddy Admin API](https://caddyserver.com/docs/api)
- [nix-darwin Launchd Services](../../modules/services/caddy/darwin.nix)
