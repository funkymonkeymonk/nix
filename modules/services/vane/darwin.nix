# Vane native launchd service for Darwin (macOS)
# Runs Vane directly (not in Docker), using the Nix package.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.vane;
  bifrostCfg = config.myConfig.bifrost;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  dataDir = cfg.dataDir;

  bifrostEnabled = bifrostCfg.enable && bifrostCfg.upstreams != {};

  resolvedBaseUrl =
    if cfg.openaiBaseUrl != null
    then cfg.openaiBaseUrl
    else if bifrostEnabled
    then "http://localhost:${toString bifrostCfg.port}/v1"
    else "http://localhost:8000/v1";

  resolvedProviderId =
    if bifrostEnabled
    then "bifrost"
    else "vllm-mlx-local";

  resolvedProviderName =
    if bifrostEnabled
    then "Bifrost Gateway (local)"
    else "vllm-mlx Gateway (local)";

  resolvedProviderApiKey =
    if bifrostEnabled
    then "bifrost"
    else "vllm-mlx-local";

  defaultChatModels = let
    model =
      if cfg.defaultModel != null
      then cfg.defaultModel
      else "deepseek-r1:14b";
  in [
    {
      name = model;
      key = model;
    }
  ];

  chatModels =
    if cfg.chatModels != {}
    then
      map (model: {
        name = model.name;
        key = model.key;
      }) (builtins.attrValues cfg.chatModels)
    else defaultChatModels;

  modelProvider =
    {
      id = resolvedProviderId;
      name = resolvedProviderName;
      type = "openai";
      chatModels = chatModels;
      config = {
        apiKey = resolvedProviderApiKey;
        baseURL = resolvedBaseUrl;
      };
    }
    // optionalAttrs (cfg.embeddingModel != null) {
      embeddingModels = [
        {
          name = cfg.embeddingModel;
          key = cfg.embeddingModel;
        }
      ];
    };

  vaneConfig = builtins.toJSON ({
      version = 1;
      setupComplete = true;
      modelProviders = [modelProvider];
    }
    // optionalAttrs (cfg.searxngUrl != null) {
      search = {
        searxngURL = cfg.searxngUrl;
      };
    });

  playwrightBrowsers = pkgs.playwright-driver.browsers;

  # Environment for Vane
  # OPENAI_BASE_URL is omitted — it triggers Vane to auto-create a duplicate provider.
  # The base URL is set in the pre-created config.json instead.
  vaneEnv =
    {
      VANE_PORT = toString cfg.port;
      PLAYWRIGHT_BROWSERS_PATH = "${playwrightBrowsers}";
    }
    // optionalAttrs (cfg.searxngUrl != null) {
      SEARXNG_API_URL = cfg.searxngUrl;
    }
    // optionalAttrs (cfg.ollamaUrl != null) {
      OLLAMA_API_URL = cfg.ollamaUrl;
    };

  vaneServiceScript = pkgs.writeShellScript "vane-launchd-service" ''
    set -euo pipefail
    export HOME="${darwinHomeDir}"
    export PATH="${pkgs.nodejs}/bin:/usr/local/bin:/usr/bin:/bin"
    export DATA_DIR="${dataDir}"

    mkdir -p "${dataDir}/data" "${dataDir}/logs"

    # Symlink drizzle directory so Vane can find migration files
    if [ ! -L "${dataDir}/drizzle" ]; then
      ln -sf "${pkgs.vane}/lib/vane/drizzle" "${dataDir}/drizzle"
    fi

    # Write Nix-managed config (always overwrites to stay in sync)
    printf '%s\n' ${lib.escapeShellArg vaneConfig} > "${dataDir}/data/config.json"

    exec ${pkgs.vane}/bin/vane
  '';
in {
  options.myConfig.vane = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Vane (AI-powered answering engine with web search, formerly Perplexica)";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port for Vane web UI";
    };

    dataDir = mkOption {
      type = types.str;
      default = "$HOME/.local/share/vane";
      description = "Directory for Vane data and configuration";
    };

    ollamaUrl = mkOption {
      type = types.nullOr types.str;
      default = "http://host.docker.internal:11434";
      description = "URL for Ollama API. For Docker on macOS, use host.docker.internal";
    };

    searxngUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        URL for a SearxNG API to use for Vane's web search. Not owned by
        the searxng service module — set this explicitly (e.g.
        "http://localhost:8080" when also running modules/services/searxng)
        to enable SearxNG-backed search. When null (default), Vane runs
        without web search rather than silently pointing at a SearxNG
        instance that may not be running on this host.
      '';
    };

    openaiApiKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "OpenAI API key for using OpenAI models (optional)";
    };

    openaiBaseUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Custom OpenAI-compatible API base URL (e.g., LiteLLM endpoint). Leave null for official OpenAI API.";
    };

    openaiBaseUrlOpnixItem = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "1Password item reference (e.g., 'op://vault/item/field') to retrieve the OpenAI base URL. When set, openaiBaseUrl can be left null.";
    };

    anthropicApiKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Anthropic API key for using Claude models (optional)";
    };

    defaultModel = mkOption {
      type = types.nullOr types.str;
      default = "deepseek-r1:14b";
      description = "Default Ollama chat model for Vane. Set to null to skip auto-configuration and configure manually via web UI.";
    };

    embeddingModel = mkOption {
      type = types.nullOr types.str;
      default = "nomic-embed-text";
      description = "Ollama embedding model for Vane vector search. Set to null to skip.";
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically start Vane service on login (recommended: false to avoid boot slowdown)";
    };

    chatModels = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Display name for the model in Vane UI";
          };
          key = mkOption {
            type = types.str;
            description = "Model key sent to the API (use 'provider-prefix/model-name' when routing through Bifrost)";
          };
        };
      });
      default = {};
      description = "Chat models exposed by Vane. If empty, falls back to the built-in vllm-mlx model configuration. When using Bifrost, set keys with provider prefix (e.g., 'vllm-mlx-local/glm47-flash-4bit')";
    };
  };

  config = mkIf cfg.enable {
    launchd.daemons.vane = {
      command = vaneServiceScript;
      serviceConfig = {
        Label = "com.vane.service";
        EnvironmentVariables = vaneEnv;
        RunAtLoad = cfg.autoStart;
        KeepAlive = true;
        UserName = primaryUser;
        StandardOutPath = "/tmp/vane.log";
        StandardErrorPath = "/tmp/vane.error.log";
        WorkingDirectory = "${darwinHomeDir}/.local/share/vane";
      };
    };

    system.activationScripts.postActivation.text = mkAfter ''
      mkdir -p "${dataDir}/data" "${dataDir}/logs"
    '';

    # Register in service registry for port conflict detection and readiness checks
    myConfig.serviceRegistry = commonLib.mkServiceRegistry "vane" {
      displayName = "Vane";
      port = cfg.port;
      label = "com.vane.service";
      errorLog = "/tmp/vane.error.log";
      enabled = cfg.enable;
    };
  };
}
