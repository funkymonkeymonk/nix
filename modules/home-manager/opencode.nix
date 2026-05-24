{
  osConfig,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.opencode;
  rtkCfg = osConfig.myConfig.llmClient.rtk;
  hmLib = import ./lib.nix {inherit lib;};

  # Filter providers that have 1Password items configured
  providersWithSecrets = lib.filterAttrs (_name: provider: provider.onePasswordItem != "") cfg.providers;

  # Filter providers that have baseURLOpnixItem configured
  providersWithBaseURLSecrets = lib.filterAttrs (_name: provider: provider.baseURLOpnixItem != "") cfg.providers;

  # Filter providers with dynamic models enabled
  providersWithDynamicModels = lib.filterAttrs (_name: provider: provider.dynamicModels or false) cfg.providers;

  # Build opnix secrets configuration using shared helper (API keys)
  opnixSecrets = hmLib.mkOpnixSecrets "opencode" osConfig.myConfig.onepassword.defaultVault (
    lib.mapAttrs (name: provider: {
      inherit (provider) onePasswordItem;
      secretPath = ".config/opencode/secrets/${name}-apikey";
    })
    providersWithSecrets
  );

  # Build opnix secrets for base URLs (providers with baseURLOpnixItem)
  opnixBaseURLSecrets = hmLib.mkOpnixSecretsGeneric "opencode" osConfig.myConfig.onepassword.defaultVault (
    lib.mapAttrs (name: provider: {
      reference = provider.baseURLOpnixItem;
      path = ".config/opencode/secrets/${name}-baseurl";
    })
    providersWithBaseURLSecrets
  );

  # Combined opnix secrets (API keys + base URLs)
  allOpnixSecrets = opnixSecrets // opnixBaseURLSecrets;

  # Build provider config with API key references (only if onePasswordItem is set)
  providerConfig =
    lib.mapAttrs (
      _name: provider: let
        hasApiKey = (provider.onePasswordItem or "") != "";
        hasModels = provider.models or {} != {};
        baseOptions = {inherit (provider) baseURL;};
        optionsWithKey = baseOptions // {apiKey = "{file:~/.config/opencode/secrets/${_name}-apikey}";};
        baseConfig =
          {
            inherit (provider) name;
            options =
              if hasApiKey
              then optionsWithKey
              else baseOptions;
          }
          # Always include static models if defined (dynamic models are added at runtime)
          // (optionalAttrs hasModels {inherit (provider) models;});
      in
        baseConfig // (optionalAttrs (provider.npm != null) {inherit (provider) npm;})
    )
    cfg.providers;

  # Transform MCP server config from our options format to opencode's expected format
  transformMcpServer = _name: server:
    {
      inherit (server) enabled;
    }
    // (
      if server.type == "remote"
      then {
        type = "remote";
        inherit (server) url;
      }
      else {
        type = "local";
        inherit (server) command;
      }
    );

  # Generate markdown command files
  commandFiles = lib.mapAttrs' (name: cmd:
    lib.nameValuePair ".config/opencode/commands/${name}.md" {
      text = let
        frontmatter = lib.concatStringsSep "\n" (
          ["---"]
          ++ optional (cmd.description != "") "description: ${cmd.description}"
          ++ optional (cmd.agent != null) "agent: ${cmd.agent}"
          ++ optional (cmd.subtask != null) "subtask: ${lib.boolToString cmd.subtask}"
          ++ optional (cmd.model != null) "model: ${cmd.model}"
          ++ ["---"]
        );
      in ''
        ${frontmatter}

        ${cmd.template}
      '';
    })
  cfg.commands;

  # Build agent config
  agentConfig = lib.mapAttrs (_name: agent:
    {
      inherit (agent) description mode;
    }
    // (optionalAttrs (agent.model != null) {
      inherit (agent) model;
    })
    // (optionalAttrs (agent.prompt != "") {
      inherit (agent) prompt;
    })
    // (optionalAttrs (agent.temperature != null) {
      inherit (agent) temperature;
    })
    // (optionalAttrs agent.hidden {
      inherit (agent) hidden;
    })
    // (optionalAttrs (agent.tools != {}) {
      inherit (agent) tools;
    })
    // (optionalAttrs (agent.permission != {}) {
      inherit (agent) permission;
    })
    // (optionalAttrs (agent.color != "") {
      inherit (agent) color;
    }))
  cfg.agents;

  # Build the dynamic model config for providers that use it
  # This is a JSON structure mapping provider name -> {baseURL, apiKeyFile, baseURLFile?}
  dynamicProvidersConfig =
    lib.mapAttrs (name: provider: {
      # Use static baseURL if set, otherwise empty (will be read from file at runtime)
      inherit (provider) baseURL;
      apiKeyFile =
        if (provider.onePasswordItem or "") != ""
        then "~/.config/opencode/secrets/${name}-apikey"
        else null;
      # If baseURLOpnixItem is set, the URL will be read from this file at runtime
      baseURLFile =
        if (provider.baseURLOpnixItem or "") != ""
        then "~/.config/opencode/secrets/${name}-baseurl"
        else null;
    })
    providersWithDynamicModels;

  dynamicProvidersJson = builtins.toJSON dynamicProvidersConfig;

  # Names of providers that use opnix-managed base URLs (for static config patching)
  providersWithBaseURLSecretNames = lib.attrNames providersWithBaseURLSecrets;

  # Script to fetch models from LiteLLM-compatible endpoints and merge into config
  fetchModelsScript = pkgs.writeShellScript "opencode-fetch-models" ''
    set -euo pipefail

    DYNAMIC_PROVIDERS='${dynamicProvidersJson}'
    BASE_CONFIG="$HOME/.config/opencode/opencode.json"
    DYNAMIC_CONFIG="$HOME/.config/opencode/opencode-dynamic.json"
    PRIVATE_CONFIG="$HOME/.config/opencode/opencode-private.json"

    # Start with the base config
    if [[ -L "$BASE_CONFIG" ]]; then
      # It's a symlink (from nix store), read it
      cp "$(readlink -f "$BASE_CONFIG")" "$DYNAMIC_CONFIG"
    elif [[ -f "$BASE_CONFIG" ]]; then
      cp "$BASE_CONFIG" "$DYNAMIC_CONFIG"
    else
      echo "{}" > "$DYNAMIC_CONFIG"
    fi

    # Patch baseURLs from opnix-managed secret files
    # This allows provider base URLs to be stored in 1Password instead of the Nix store
    ${lib.optionalString (providersWithBaseURLSecretNames != []) ''
      for provider_name in ${lib.concatStringsSep " " providersWithBaseURLSecretNames}; do
        url_file="$HOME/.config/opencode/secrets/''${provider_name}-baseurl"
        if [[ -f "$url_file" ]]; then
          url=$(cat "$url_file")
          ${pkgs.jq}/bin/jq --arg p "$provider_name" --arg url "$url" \
            '.provider[$p].options.baseURL = $url' "$DYNAMIC_CONFIG" > "$DYNAMIC_CONFIG.tmp" \
            && mv "$DYNAMIC_CONFIG.tmp" "$DYNAMIC_CONFIG"
          echo "Patched baseURL for provider $provider_name from secret file" >&2
        fi
      done
    ''}

    # Function to fetch models from a provider
    fetch_provider_models() {
      local provider_name="$1"
      local base_url="$2"
      local api_key_file="$3"

      local auth_header=""
      if [[ -n "$api_key_file" ]] && [[ -f "''${api_key_file/#\~/$HOME}" ]]; then
        local api_key
        api_key=$(cat "''${api_key_file/#\~/$HOME}")
        auth_header="Authorization: Bearer $api_key"
      fi

      # Try to fetch models from /v1/models endpoint
      local models_response
      if [[ -n "$auth_header" ]]; then
        models_response=$(${pkgs.curl}/bin/curl -s --connect-timeout 5 --max-time 10 \
          -H "$auth_header" \
          "''${base_url}/v1/models" 2>/dev/null || echo '{"data":[]}')
      else
        models_response=$(${pkgs.curl}/bin/curl -s --connect-timeout 5 --max-time 10 \
          "''${base_url}/v1/models" 2>/dev/null || echo '{"data":[]}')
      fi

      # Parse the response and extract model IDs
      echo "$models_response" | ${pkgs.jq}/bin/jq -r '.data[]?.id // empty' 2>/dev/null || true
    }

    # Process each dynamic provider
    echo "$DYNAMIC_PROVIDERS" | ${pkgs.jq}/bin/jq -r 'to_entries[] | "\(.key)|\(.value.baseURL)|\(.value.apiKeyFile // "")|\(.value.baseURLFile // "")"' | while IFS='|' read -r provider_name base_url api_key_file base_url_file; do
      # If a baseURLFile is specified, read the URL from it (overrides static baseURL)
      if [[ -n "$base_url_file" ]]; then
        resolved_url_file="''${base_url_file/#\~/$HOME}"
        if [[ -f "$resolved_url_file" ]]; then
          base_url=$(cat "$resolved_url_file")
        fi
      fi

      if [[ -z "$base_url" ]]; then
        continue
      fi

      echo "Fetching models from $provider_name ($base_url)..." >&2

      # Fetch models
      models=$(fetch_provider_models "$provider_name" "$base_url" "$api_key_file")

      if [[ -n "$models" ]]; then
        # Build a models object for this provider
        models_obj=$(echo "$models" | ${pkgs.jq}/bin/jq -Rs 'split("\n") | map(select(length > 0)) | map({(.): {name: .}}) | add // {}')

        # Merge into the dynamic config
        ${pkgs.jq}/bin/jq --arg provider "$provider_name" --argjson models "$models_obj" '
          .provider[$provider].models = ((.provider[$provider].models // {}) + $models)
        ' "$DYNAMIC_CONFIG" > "$DYNAMIC_CONFIG.tmp" && mv "$DYNAMIC_CONFIG.tmp" "$DYNAMIC_CONFIG"

        echo "  Found $(echo "$models" | wc -l | tr -d ' ') models" >&2
      else
        echo "  No models found or fetch failed" >&2
      fi
    done

    # Merge private config (machine-local sensitive settings, e.g. MCP servers)
    # This file is NOT managed by Nix - create it manually at $PRIVATE_CONFIG
    if [[ -f "$PRIVATE_CONFIG" ]]; then
      echo "Merging private config from $PRIVATE_CONFIG..." >&2
      ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$DYNAMIC_CONFIG" "$PRIVATE_CONFIG" \
        > "$DYNAMIC_CONFIG.tmp" && mv "$DYNAMIC_CONFIG.tmp" "$DYNAMIC_CONFIG"
    fi

    echo "$DYNAMIC_CONFIG"
  '';

  # Wrapped opencode binary that fetches dynamic models before launching
  opencodeWrapped = pkgs.writeShellScriptBin "opencode" ''
    OPENCODE_CONFIG=$(${fetchModelsScript})
    export OPENCODE_CONFIG
    exec ${pkgs.opencode}/bin/opencode "$@"
  '';

  # Build complete settings (TUI-specific keys like theme go in tui.json, not here)
  settings =
    {
      inherit (cfg) autoupdate;
      mcp =
        {
          devenv = {
            type = "local";
            command = ["devenv" "mcp"];
            enabled = true;
          };
        }
        // lib.mapAttrs transformMcpServer cfg.extraMcpServers;
      permission = {
        bash = {
          "task *" = "allow";
          "npx *" = "allow";
          "npm *" = "allow";
        };
      };
      tools = {
        devenv = true;
      };
    }
    // (optionalAttrs (cfg.model != null) {
      inherit (cfg) model;
    })
    // (optionalAttrs (cfg.disabledProviders != []) {
      disabled_providers = cfg.disabledProviders;
    })
    // (optionalAttrs (cfg.providers != {}) {
      provider = providerConfig;
    })
    // (optionalAttrs (cfg.agents != {}) {
      agent = agentConfig;
    });
in {
  config = mkIf cfg.enable {
    # Replace the opencode binary with a wrapper that:
    # 1. Fetches dynamic models (when dynamic providers are configured)
    # 2. Merges ~/.config/opencode/opencode-private.json (always, if the file exists)
    # The wrapper is always installed so the private config merge always applies.
    home.packages = [
      (lib.hiPrio opencodeWrapped)
    ];

    # RTK instructions file for OpenCode (only when RTK is enabled) + command files
    home.file =
      {
        # TUI configuration - must be kept in sync with main config theme
        ".config/opencode/tui.json" = {
          force = true;
          text = builtins.toJSON {
            "$schema" = "https://opencode.ai/tui.json";
            inherit (cfg) theme;
          };
        };
      }
      // (optionalAttrs rtkCfg.enable {
        ".config/opencode/RTK.md" = {
          text = ''
            # RTK Token Optimization

            Use RTK-prefixed commands for token-efficient output:

            | Standard Command | RTK Equivalent | Token Savings |
            |------------------|---------------|---------------|
            | `git status` | `rtk git status` | ~80% |
            | `git diff` | `rtk git diff` | ~75% |
            | `git log` | `rtk git log` | ~80% |
            | `git push` | `rtk git push` | ~92% |
            | `ls` | `rtk ls` | ~80% |
            | `cat <file>` | `rtk read <file>` | ~70% |
            | `grep` | `rtk grep` | ~80% |
            | `cargo test` | `rtk cargo test` | ~90% |
            | `npm test` | `rtk npm test` | ~90% |
            | `ruff check` | `rtk ruff check` | ~80% |
            | `pytest` | `rtk pytest` | ~90% |
            | `docker ps` | `rtk docker ps` | ~80% |

            Check savings: \`rtk gain\` or \`rtk gain --graph\`
          '';
        };
      })
      // commandFiles;

    programs = {
      # Use home-manager's native programs.opencode
      opencode = {
        enable = true;
        settings = let
          # Build instructions list: RTK docs + any auto-loaded skills
          instructionFiles =
            lib.optional rtkCfg.enable "RTK.md"
            ++ ["skills/auto-loaded.md"];
        in
          settings
          // {instructions = instructionFiles;};
      };

      # Configure opnix secrets for providers with 1Password items (API keys + base URLs)
      onepassword-secrets = mkIf ((allOpnixSecrets != {}) && osConfig.myConfig.onepassword.enable) {
        enable = true;
        secrets = allOpnixSecrets;
      };
    };
  };
}
