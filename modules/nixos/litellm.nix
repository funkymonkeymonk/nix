# LiteLLM service module for NixOS (Linux)
#
# Uses systemd to manage LiteLLM as a system service
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.litellm;

  # Generate a random master key placeholder if not provided
  defaultMasterKey = "sk-litellm-REPLACE-WITH-1PASSWORD-SECRET";

  # Helper to convert string to uppercase for env var names
  toUpper = str:
    builtins.replaceStrings
    ["a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z" "-"]
    ["A" "B" "C" "D" "E" "F" "G" "H" "I" "J" "K" "L" "M" "N" "O" "P" "Q" "R" "S" "T" "U" "V" "W" "X" "Y" "Z" "_"]
    str;

  # Build the config.yaml content
  configContent = let
    # Default models configuration
    defaultModels =
      [
        {
          model_name = "ollama/llama3.2";
          litellm_params = {
            model = "ollama/llama3.2";
            api_base = cfg.ollamaBaseUrl;
          };
        }
        {
          model_name = "ollama/llama3.2:8b";
          litellm_params = {
            model = "ollama/llama3.2:8b";
            api_base = cfg.ollamaBaseUrl;
          };
        }
        {
          model_name = "ollama/qwen2.5-coder:14b";
          litellm_params = {
            model = "ollama/qwen2.5-coder:14b";
            api_base = cfg.ollamaBaseUrl;
          };
        }
      ]
      ++ optionals (cfg.anthropicApiKey != "" || cfg.anthropicApiKeyOnePassword != "") [
        {
          model_name = "claude-3-5-sonnet";
          litellm_params = {
            model = "claude-3-5-sonnet-20241022";
          };
        }
        {
          model_name = "claude-3-opus";
          litellm_params = {
            model = "claude-3-opus-20240229";
          };
        }
        {
          model_name = "claude-3-5-haiku";
          litellm_params = {
            model = "claude-3-5-haiku-20241022";
          };
        }
      ]
      ++ optionals (cfg.openaiApiKey != "" || cfg.openaiApiKeyOnePassword != "") [
        {
          model_name = "gpt-4o";
          litellm_params = {
            model = "gpt-4o";
          };
        }
        {
          model_name = "gpt-4o-mini";
          litellm_params = {
            model = "gpt-4o-mini";
          };
        }
      ];

    # Combine default and user-defined models
    allModels =
      defaultModels
      ++ (map (m: let
          # Find if this model's apiBase matches an extraProvider
          matchingProvider =
            findFirst (
              name:
                (cfg.extraProviders.${name}.apiBase or "") == (m.litellmParams.apiBase or "")
            )
            null (attrNames cfg.extraProviders);
        in {
          model_name = m.modelName;
          litellm_params =
            {
              model = m.litellmParams.model;
            }
            // optionalAttrs (m.litellmParams.apiBase != null) {
              api_base = m.litellmParams.apiBase;
            }
            // optionalAttrs (matchingProvider != null) {
              api_key = "os.environ/${toUpper matchingProvider}_API_KEY";
            };
        })
        cfg.models);

    configYaml = {
      model_list = allModels;
      litellm_settings = {
        drop_params = true;
        set_verbose = cfg.logLevel == "DEBUG";
      };
      general_settings = {
        master_key =
          if cfg.masterKey != ""
          then cfg.masterKey
          else defaultMasterKey;
      };
    };
  in
    builtins.toJSON configYaml;

  # Write config file
  configFile = pkgs.writeText "litellm-config.yaml" configContent;

  # Script to build environment and start LiteLLM
  litellmStartScript = pkgs.writeShellScript "litellm-start" ''
    set -euo pipefail

    # Set up environment variables for API keys
    ${optionalString (cfg.anthropicApiKey != "") "export ANTHROPIC_API_KEY='${cfg.anthropicApiKey}'"}
    ${optionalString (cfg.openaiApiKey != "") "export OPENAI_API_KEY='${cfg.openaiApiKey}'"}
    ${optionalString (cfg.saltKey != "") "export LITELLM_SALT_KEY='${cfg.saltKey}'"}
    ${optionalString (cfg.databaseUrl != "") "export DATABASE_URL='${cfg.databaseUrl}'"}

    # 1Password integration - fetch secrets at runtime
    ${optionalString (cfg.masterKeyOnePassword != "") ''
      if command -v op &> /dev/null; then
        export LITELLM_MASTER_KEY="$(op read '${cfg.masterKeyOnePassword}' 2>/dev/null || echo '${defaultMasterKey}')"
      fi
    ''}
    ${optionalString (cfg.saltKeyOnePassword != "") ''
      if command -v op &> /dev/null; then
        export LITELLM_SALT_KEY="$(op read '${cfg.saltKeyOnePassword}' 2>/dev/null || echo "")"
      fi
    ''}
    ${optionalString (cfg.databaseUrlOnePassword != "") ''
      if command -v op &> /dev/null; then
        export DATABASE_URL="$(op read '${cfg.databaseUrlOnePassword}' 2>/dev/null || echo "")"
      fi
    ''}
    ${optionalString (cfg.anthropicApiKeyOnePassword != "") ''
      if command -v op &> /dev/null; then
        export ANTHROPIC_API_KEY="$(op read '${cfg.anthropicApiKeyOnePassword}' 2>/dev/null || echo "")"
      fi
    ''}
    ${optionalString (cfg.openaiApiKeyOnePassword != "") ''
      if command -v op &> /dev/null; then
        export OPENAI_API_KEY="$(op read '${cfg.openaiApiKeyOnePassword}' 2>/dev/null || echo "")"
      fi
    ''}

    # Extra providers from 1Password
    ${concatStringsSep "\n" (mapAttrsToList (name: provider: ''
        ${optionalString (provider.apiKeyOnePassword != "") ''
          if command -v op &> /dev/null; then
            export ${toUpper name}_API_KEY="$(op read '${provider.apiKeyOnePassword}' 2>/dev/null || echo "")"
          fi
        ''}
      '')
      cfg.extraProviders)}

    CONFIG_FILE="${
      if cfg.configFile != null
      then cfg.configFile
      else configFile
    }"

    echo "Starting LiteLLM proxy on ${cfg.host}:${toString cfg.port}..."
    exec ${pkgs.litellm}/bin/litellm \
      --config "$CONFIG_FILE" \
      --host ${cfg.host} \
      --port ${toString cfg.port} \
      --detailed_debug
  '';
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.litellm];

    systemd.services.litellm = {
      description = "LiteLLM Proxy Server";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "ollama.service"];
      wants = ["ollama.service"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${litellmStartScript}";
        Restart = "on-failure";
        RestartSec = "10s";
        Environment = [
          "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
        ];
      };
    };

    # Open firewall if binding to non-localhost
    networking.firewall.allowedTCPPorts = mkIf (cfg.host != "127.0.0.1") [cfg.port];
  };
}
