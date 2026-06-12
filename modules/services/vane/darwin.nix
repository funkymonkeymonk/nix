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
  inherit (config._vaneCommon) searxngUrl;

  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "monkey";
  darwinHomeDir = "/Users/${primaryUser}";
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
    else "vmlx-local";

  resolvedProviderName =
    if bifrostEnabled
    then "Bifrost Gateway (local)"
    else "vMLX Gateway (local)";

  resolvedProviderApiKey =
    if bifrostEnabled
    then "bifrost"
    else "vmlx-local";

  defaultChatModels = let
    model =
      if cfg.defaultModel != null
      then cfg.defaultModel
      else "deepseek-r1:14b";
  in
    if bifrostEnabled
    then [
      {
        name = model;
        key = "vllm/${model}";
      }
    ]
    else [
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

  modelProvider = {
    id = resolvedProviderId;
    name = resolvedProviderName;
    type = "openai";
    chatModels = chatModels;
    embeddingModels = [];
    config = {
      apiKey = resolvedProviderApiKey;
      baseURL = resolvedBaseUrl;
    };
  };

  vaneConfig = builtins.toJSON {
    version = 1;
    setupComplete = true;
    modelProviders = [modelProvider];
    search = {
      searxngURL = searxngUrl;
    };
  };

  # Environment for Vane
  # OPENAI_BASE_URL is omitted — it triggers Vane to auto-create a duplicate provider.
  # The base URL is set in the pre-created config.json instead.
  vaneEnv =
    {
      VANE_PORT = toString cfg.port;
      SEARXNG_API_URL = searxngUrl;
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
  imports = [./common.nix];

  config = mkIf cfg.enable {
    launchd.daemons.vane = {
      serviceConfig = {
        Label = "com.vane.service";
        ProgramArguments = ["${vaneServiceScript}"];
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
  };
}
