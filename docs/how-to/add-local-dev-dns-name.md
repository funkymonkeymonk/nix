# Add a Local Dev DNS Name

This guide shows how to add a route to the personal Caddy reverse proxy so your local services are accessible via clean DNS names like `http://app.localhost` instead of `http://localhost:PORT`.

## Prerequisites

- Running the system with `myConfig.caddy.enable = true` (enables Caddy + dnsmasq)
- Caddy is running and listening on `localhost:80` with admin API on `localhost:2019`
- Your local service running on a specific port (e.g., `localhost:9000`)

## Static Routes (via Nix Config)

Add permanent routes directly in your Nix configuration via `myConfig.caddy.hosts`:

```nix
{
  config.myConfig.caddy.hosts = {
    "myapp.localhost" = "localhost:9000";
    "api.localhost" = "localhost:9001";
  };
}
```

Apply the configuration:

```bash
darwin-rebuild switch --flake .
# or
nix flake update && darwin-rebuild switch --flake .
```

Verify the route is available:

```bash
curl http://myapp.localhost
```

## Dynamic Routes (via Admin API)

Add temporary routes on-the-fly using Caddy's admin API without rebuilding the system.

### POST a Route

```bash
curl -X POST http://localhost:2019/config/apps/http/servers/srv0/routes \
  -H "Content-Type: application/json" \
  -d '{
    "@id": "my-temporary-app",
    "match": [
      {"host": ["myapp.localhost"]}
    ],
    "handle": [
      {
        "handler": "reverse_proxy",
        "upstreams": [
          {"dial": "localhost:9000"}
        ]
      }
    ]
  }'
```

Response: HTTP 200 (success) or error details.

### Verify the Route

```bash
curl -s http://localhost:2019/config/apps/http/servers/srv0/routes | jq .
```

### Delete a Route

Find the route's index in the routes array (usually 0 for newly added routes), then:

```bash
curl -X DELETE http://localhost:2019/config/apps/http/servers/srv0/routes/0
```

Or, if you assigned an `@id`, use the ID directly (depending on Caddy API version):

```bash
curl -X DELETE http://localhost:2019/config/apps/http/servers/srv0/routes/@id/my-temporary-app
```

## DNS Resolution

- **macOS native resolution**: `*.localhost` is automatically resolved to `127.0.0.1` — no `/etc/hosts` edits needed
- **dnsmasq**: Also configured to resolve `*.internal` to `127.0.0.1` on port 5353 for backward compatibility
- **Custom TLDs**: To add additional TLDs (e.g., `.dev.local`), add them to `myConfig.caddy.hosts` or use `environment.etc."resolver/<tld>"` to configure macOS DNS resolution

## Troubleshooting

### Caddy not responding

Check if Caddy is running:

```bash
launchctl list | grep caddy
# Should show: org.nixos.caddy
```

View Caddy logs:

```bash
tail -50 "$HOME/.local/share/caddy/caddy.log"
tail -50 "$HOME/.local/share/caddy/caddy.error.log"
```

### dnsmasq not resolving

Check dnsmasq status:

```bash
launchctl list | grep dnsmasq
# Should show: org.nixos.dnsmasq
```

Test DNS resolution:

```bash
dig +short myapp.localhost @127.0.0.1 -p 5353
# Should return: 127.0.0.1
```

### Port 80 Permission Denied

Caddy requires elevated privileges to bind to port 80. On macOS with nix-darwin, launchd runs the service with appropriate capabilities. If you see "permission denied", verify:

- Caddy service is running as your user (not root)
- `launchctl list org.nixos.caddy` shows the service is loaded
- No other process is listening on port 80: `lsof -i :80`

## See Also

- [Caddy Admin API Reference](https://caddyserver.com/docs/api)
- [Caddy Caddyfile Syntax](https://caddyserver.com/docs/caddyfile/concepts)
- [nix-darwin Launchd Services](../../modules/services/caddy/darwin.nix)
