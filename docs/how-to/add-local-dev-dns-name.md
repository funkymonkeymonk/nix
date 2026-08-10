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
curl http://localhost:2019/config/apps/http/servers/http/routes
```

### Add a Dynamic Route

```bash
# Add route for a new service
curl -X POST http://localhost:2019/config/apps/http/servers/http/routes \
  -H "Content-Type: application/json" \
  -d '{
    "match": [{"host": ["newapp.internal"]}],
    "handle": [{
      "handler": "reverse_proxy",
      "upstreams": [{"dial": "localhost:5000"}]
    }]
  }'
```

### Query a Specific Route

```bash
curl http://localhost:2019/config/apps/http/servers/http/routes/0
```

### Delete a Route

```bash
curl -X DELETE http://localhost:2019/config/apps/http/servers/http/routes/0
```

## localhost Domain Support

By default, Caddy resolves:
- `*.internal` → `127.0.0.1` (via dnsmasq)
- `localhost` → `127.0.0.1` (OS default)

To use `.localhost` domains, add them as static routes:

```nix
myConfig.caddy.hosts = {
  "myapp.localhost" = "localhost:3000";
};
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

### Route Not Working

1. Verify the route is configured:
   ```bash
   curl http://localhost:2019/config/apps/http/servers/http/routes | jq .
   ```

2. Check Caddy logs:
   ```bash
   tail -f /tmp/caddy.log
   ```

3. Test the upstream service is running:
   ```bash
   curl http://localhost:3000/
   ```

## See Also

- [Caddy Reverse Proxy Documentation](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Caddy Admin API](https://caddyserver.com/docs/api)
- [Integrate devenv with Local Caddy](integrate-devenv-with-local-caddy.md)
