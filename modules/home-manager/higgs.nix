# Higgs LLM inference server configuration
# Generates ~/.config/higgs/config.toml
{
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.higgs;
  hmLib = import ./lib.nix {inherit lib;};
  tomlFormat = pkgs.formats.toml {};

  # Remove null values recursively for TOML cleanliness
  clean = v:
    if isAttrs v && !isList v
    then filterAttrs (_: val: val != null && val != "") (mapAttrs (_: clean) v)
    else v;

  serverConfig = clean {
    host = cfg.server.host;
    port = cfg.server.port;
    max_tokens = cfg.server.maxTokens;
    timeout = cfg.server.timeout;
    max_body_size = cfg.server.maxBodySize;
    rate_limit = cfg.server.rateLimit;
  };

  localConfig = clean {
    mlx_profile = cfg.local.mlxProfile;
    raise_wired_limit = cfg.local.raiseWiredLimit;
  };

  modelsConfig = map (m:
    clean {
      path = m.path;
      name = m.name;
      mlx_profile = m.mlxProfile;
      batch = m.batch;
      kv_cache = m.kvCache;
      kv_bits = m.kvBits;
      kv_key_bits = m.kvKeyBits;
      kv_value_bits = m.kvValueBits;
      kv_norm_correction = m.kvNormCorrection;
      kv_adaptive_dense_layers = m.kvAdaptiveDenseLayers;
      kv_seed = m.kvSeed;
    })
  cfg.models;

  # Providers that have opnix-managed API keys (resolved at runtime)
  providersWithOpnixSecrets = filterAttrs (_name: p: p.apiKeyOpnixItem != null) cfg.providers;

  # Build opnix secrets (API keys from 1Password)
  opnixSecrets = hmLib.mkOpnixSecretsGeneric "higgs" osConfig.myConfig.onepassword.defaultVault (
    mapAttrs (name: p: {
      reference = p.apiKeyOpnixItem;
      path = ".config/higgs/secrets/${name}-apikey";
    })
    providersWithOpnixSecrets
  );

  # Providers with apiKeyFile (read at build time, embed in config)
  providersConfig = mapAttrs (name: p:
    clean (
      {
        url = p.url;
        format = p.format;
        strip_auth = p.stripAuth;
        stub_count_tokens = p.stubCountTokens;
      }
      // optionalAttrs (p.apiKeyFile != null && p.apiKeyOpnixItem == null) {
        api_key = builtins.readFile p.apiKeyFile;
      }
    ))
  cfg.providers;

  routesConfig = map (r:
    clean {
      pattern = r.pattern;
      provider = r.provider;
      model = r.model;
      name = r.name;
      description = r.description;
    })
  cfg.routes;

  defaultConfig = clean {
    provider = cfg.default.provider;
  };

  autoRouterConfig = clean {
    enabled = cfg.autoRouter.enable;
    model = cfg.autoRouter.model;
    timeout_ms = cfg.autoRouter.timeoutMs;
  };

  retentionConfig = clean {
    enabled = cfg.retention.enable;
    minutes = cfg.retention.minutes;
  };

  loggingMetricsConfig =
    clean {
      enabled = cfg.logging.metrics.enable;
      max_size_mb = cfg.logging.metrics.maxSizeMb;
      max_files = cfg.logging.metrics.maxFiles;
    }
    // optionalAttrs (cfg.logging.metrics.path != null) {
      path = cfg.logging.metrics.path;
    };

  # Build the full toml config structure, adding sections only when they have content
  tomlConfig =
    {server = serverConfig;}
    // optionalAttrs (localConfig != {}) {local = localConfig;}
    // optionalAttrs (modelsConfig != []) {models = modelsConfig;}
    // optionalAttrs (providersConfig != {}) {provider = providersConfig;}
    // optionalAttrs (routesConfig != []) {routes = routesConfig;}
    // {default = defaultConfig;}
    // optionalAttrs (autoRouterConfig != {}) {auto_router = autoRouterConfig;}
    // optionalAttrs (retentionConfig != {}) {retention = retentionConfig;}
    // optionalAttrs (loggingMetricsConfig != {}) {logging = {metrics = loggingMetricsConfig;};};

  hasOpnixSecrets = providersWithOpnixSecrets != {};

  # Script that patches opnix-managed API keys into the Higgs config file
  # Each provider name is passed as an argument to keep quoting simple
  providerNames = builtins.attrNames providersWithOpnixSecrets;
  patchScript = pkgs.writeShellScript "patch-higgs-api-keys" ''
    set -euo pipefail
    CONFIG="$HOME/.config/higgs/config.toml"
    ${concatStringsSep "\n" (map (name: ''
        NAME='${name}'
        KEY_FILE="$HOME/.config/higgs/secrets/$NAME-apikey"
        if [ -f "$KEY_FILE" ] && [ -f "$CONFIG" ]; then
          KEY=$(cat "$KEY_FILE")
          HEADER="[provider.$NAME]"
          if grep -qF "$HEADER" "$CONFIG"; then
            ${pkgs.gnused}/bin/sed -i.bak -e "/^\[provider\.$NAME\]/,/^\[/{
              /^api_key = /d
            }" "$CONFIG"
            ${pkgs.gnused}/bin/sed -i.bak -e "/^\[provider\.$NAME\]/a\\
            api_key = \"$KEY\"" "$CONFIG"
            rm -f "$CONFIG.bak"
          fi
        fi
      '')
      providerNames)}
  '';
in {
  config = mkIf cfg.enable {
    xdg.configFile."higgs/config.toml" = {
      source = tomlFormat.generate "config.toml" tomlConfig;
      force = true;
    };

    # Register opnix secrets for providers with 1Password items
    programs.onepassword-secrets = mkIf (hasOpnixSecrets && osConfig.myConfig.onepassword.enable) {
      enable = true;
      secrets = opnixSecrets;
    };

    # Patch API keys into config during activation (after opnix creates secret files)
    home.activation.patchHiggsApiKeys = mkIf hasOpnixSecrets (
      lib.hm.dag.entryAfter ["postActivation"] ''
        ${patchScript}
      ''
    );

    # Add higgs shell integration
    programs.zsh.initContent = mkAfter ''
      # Higgs shell integration
      if command -v higgs &>/dev/null; then
        eval "$(higgs shellenv 2>/dev/null)"
      fi
    '';
  };
}
