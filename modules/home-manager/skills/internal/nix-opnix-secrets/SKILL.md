---
name: nix-opnix-secrets
description: >
  Use when managing 1Password secrets via Nix on nix-darwin.
  Triggers on: adding API keys, tokens, or credentials to service configs;
  wiring opnix 1Password items into home-manager modules;
  creating opnix-managed secret files with activation script ordering.
---

# Nix Opnix Secrets

## Overview

Wire 1Password items into Nix-managed configs via opnix. The flow: define a 1Password reference → opnix writes it to a file during activation → your service reads the file at runtime.

## When to Use

- Adding an API key to a service config without putting it in the nix store
- Connecting a home-manager module to a 1Password item
- Creating secret files that get patched into configs during activation

## Core Pattern

### Define the Secret

In your target config, add an `apiKeyOpnixItem` or `onePasswordItem` option pointing to a 1Password reference:

```nix
providers.opencode-go = {
  url = "https://opencode.ai/zen/go/v1";
  format = "openai";
  apiKeyOpnixItem = "op://VaultName/Item Name/credential";
};
```

### Create the Secret File (home-manager module)

Use `mkOpnixSecretsGeneric` to register secrets with the opnix infrastructure:

```nix
{ lib, osConfig, ... }:
let
  hmLib = import ./lib.nix {inherit lib;};
  providersWithSecrets = filterAttrs (_name: p: p.apiKeyOpnixItem != null) cfg.providers;

  opnixSecrets = hmLib.mkOpnixSecretsGeneric "my-service" osConfig.myConfig.onepassword.defaultVault (
    mapAttrs (name: p: {
      reference = p.apiKeyOpnixItem;
      path = ".config/my-service/secrets/${name}-apikey";
    })
    providersWithSecrets
  );
in {
  config = mkIf (hasSecrets && osConfig.myConfig.onepassword.enable) {
    programs.onepassword-secrets = {
      enable = true;
      secrets = opnixSecrets;
    };
  };
}
```

### Patch Into Config at Runtime (activation script)

Read the secret file and inject it into the generated config. Use `lib.hm.dag.entryAfter` to control ordering:

```nix
patchScript = pkgs.writeShellScript "patch-my-service-keys" ''
  NAME="opencode-go"
  KEY_FILE="$HOME/.config/my-service/secrets/$NAME-apikey"
  CONFIG="$HOME/.config/my-service/config.toml"
  if [ -f "$KEY_FILE" ] && [ -f "$CONFIG" ]; then
    KEY=$(cat "$KEY_FILE")
    HEADER="[provider.$NAME]"
    if grep -qF "$HEADER" "$CONFIG"; then
      sed -i.bak -e "/^$HEADER/,/^\[/{
        /^api_key = /d
      }" "$CONFIG"
      sed -i.bak -e "/^$HEADER/a\\
api_key = \"$KEY\"" "$CONFIG"
    fi
  fi
'';

# In config:
home.activation.patchMyServiceKeys = mkIf hasSecrets (
  lib.hm.dag.entryAfter ["writeBoundary"] ''
    ${patchScript}
  ''
);
```

## Activation Ordering

| Phase | What Happens |
|-------|-------------|
| `linkGeneration` | xdg.configFile symlinks created |
| `writeBoundary` | Config files finalized |
| `installPackages` | opnix resolves 1Password items |
| `postActivation` | Last phase (use for late patching if needed) |

If the patch script runs before the opnix file exists, use a later phase:

```nix
lib.hm.dag.entryAfter ["installPackages"] ''
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Secret file doesn't exist at activation time | Move `entryAfter` to `["installPackages"]` or later |
| `writeShellScriptBin` gives "Is a directory" error | Use `writeShellScript` instead |
| Vault not found (`vaultNotFound`) | Check `op item list` — item may be in a different vault |
| Reference spaces mis-encoded | Quote the item name: `op://Vault/Item Name/field` |

## Reference: mkOpnixSecretsGeneric

```nix
# Signature:
mkOpnixSecretsGeneric:
  namespace: str       # e.g. "higgs", "vane"
  defaultVault: str    # e.g. "Opnix"
  items: [{
    reference: str     # 1Password reference
    path: str          # relative path for the secret file
  }]
  → { name = { ... }; }
```

The generated file path is `~/<path>` (e.g., `~/.config/higgs/secrets/opencode-go-apikey`).
