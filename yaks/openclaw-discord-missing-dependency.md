# Yak: nix-openclaw Discord Plugin Missing Dependency

**Status:** open  
**Priority:** medium  
**Created:** 2026-05-11  
**Labels:** bug, upstream, nix-openclaw, workaround-implemented

## Problem

The Discord plugin in nix-openclaw fails to start with error:
```
Cannot find package 'openclaw' imported from 
/Users/monkey/.openclaw-wadsworth/plugin-runtime-deps/openclaw-2026.4.22-*/dist/extensions/discord/provider-*.js
```

## Root Cause

The nix-openclaw flake doesn't properly include the 'openclaw' package in the Discord plugin's runtime dependencies (node_modules). When the Discord plugin tries to import 'openclaw', it fails because the package is not available in the plugin runtime deps directory.

## Workaround Implemented

Added activation script that creates a symlink from the nix store openclaw package to the plugin runtime deps node_modules:

```bash
ln -sf "${pkgs.openclaw}/lib/openclaw" \
  "$PLUGIN_DEPS_DIR/openclaw-*/node_modules/openclaw"
```

Location: `targets/darwin-server/default.nix` in `home.activation.injectDiscordToken`

## Upstream Issue

Needs to be reported to: https://github.com/openclaw/nix-openclaw

### Proposed Fix

The nix-openclaw flake should ensure that the 'openclaw' package is included in the plugin runtime dependencies. This could be done by:

1. Adding openclaw to the bundled plugin dependencies in the nix expression
2. Or ensuring the plugin runtime deps generation includes the parent package

### Reference

- Error occurs in: `plugin-runtime-deps/openclaw-*/dist/extensions/discord/provider-*.js`
- Missing import: `import 'openclaw'`
- Working version: nix-openclaw (latest from github:openclaw/nix-openclaw)

## Test to Verify Fix

After upstream fix is applied:
1. Remove the workaround from `targets/darwin-server/default.nix`
2. Rebuild: `darwin-rebuild switch --flake .#darwin-server --impure`
3. Check Discord plugin starts without error:
   ```bash
   tail -f /var/folders/*/T/openclaw-*/openclaw-*.log | grep -i discord
   ```
4. Should see: `[discord] client initialized as X (Wadsworth)` without errors

## Notes

- The workaround is safe to keep even after upstream fix - it will just skip if symlink already exists
- Other channels (Matrix, Slack, etc.) may also need this fix if they import 'openclaw'
- Related to how nix-openclaw handles bundled plugin runtime dependencies
