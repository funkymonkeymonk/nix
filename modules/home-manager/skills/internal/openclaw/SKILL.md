# OpenClaw Development

Guidelines for working with OpenClaw AI assistant in this repository.

## Documentation Reference

Always consult the official OpenClaw documentation before making changes:

- **Main docs**: https://docs.openclaw.ai/
- **Gateway config**: https://docs.openclaw.ai/gateway/configuration
- **Dashboard/WebUI**: https://docs.openclaw.ai/web/dashboard
- **LLMs.txt index**: https://docs.openclaw.ai/llms.txt

## Common Tasks

### Exposing Dashboard on Network

Use `gateway.bind = "lan"` (not `"0.0.0.0"` - the module uses enum values):

```nix
config.gateway = {
  bind = "lan";  # Valid values: null, "auto", "lan", "loopback", "custom", "tailnet"
};
```

### Finding Configuration Options

The nix-openclaw module defines types for all config options. Check the module source:
- https://github.com/openclaw/nix-openclaw for option types and valid values

### Auth Token Location

On Darwin with home-manager:
```
~/.openclaw-<instance>/openclaw.json -> gateway.auth.token
```

## Validation

Before pushing OpenClaw changes:
1. Check the option type in nix-openclaw module
2. Verify bind modes and auth modes match expected enum values
3. Test on target system if possible
