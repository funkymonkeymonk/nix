# Bifrost AI gateway launched service for Darwin (macOS)
# Runs bifrost-http as a foreground process, managed by launchd.
# Bifrost proxies all AI requests to upstream inference servers (vMLX, ds4, etc.)
# and exposes them through a single OpenAI-compatible API.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.bifrost;

  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "monkey";
  darwinHomeDir = "/Users/${primaryUser}";
  appDir = cfg.appDir;

  upstreamList = mapAttrsToList (name: value: value // {inherit name;}) cfg.upstreams;

  mkOpenaiProviderKey = upstream: {
    name = "${upstream.name}-key";
    value = upstream.apiKey;
    models =
      if upstream.models != []
      then upstream.models
      else ["*"];
    weight = 1.0;
  };

  mkOpenaiProvider = upstreams: {
    keys = map mkOpenaiProviderKey upstreams;
    network_config = {
      base_url = (builtins.head upstreams).url;
      allow_private_network = (builtins.head upstreams).allowPrivateNetwork;
      default_request_timeout_in_seconds = (builtins.head upstreams).requestTimeout;
    };
    custom_provider_config = {
      base_provider_type = "openai";
      allowed_requests = {
        list_models = true;
        chat_completion = true;
        chat_completion_stream = true;
        embedding = true;
      };
      request_path_overrides = {
        chat_completion = "/v1/chat/completions";
        chat_completion_stream = "/v1/chat/completions";
        embedding = "/v1/embeddings";
      };
    };
  };

  mkVllmKeyForModel = upstream: modelName: {
    name = "${upstream.name}-${modelName}-key";
    value = upstream.apiKey;
    models = [modelName];
    weight = 1.0;
    vllm_key_config = {
      url = upstream.url;
      model_name = modelName;
    };
  };

  mkVllmProvider = upstreams: let
    upstreamKeys =
      flatten (map (u: map (modelName: mkVllmKeyForModel u modelName) u.models) upstreams);
    firstUpstream = builtins.head upstreams;
  in {
    keys = upstreamKeys;
    network_config = {
      allow_private_network = firstUpstream.allowPrivateNetwork;
      default_request_timeout_in_seconds = firstUpstream.requestTimeout;
    };
  };

  providers = let
    vllmUpstreams = filter (u: u.type == "vllm") upstreamList;
    openaiUpstreams = filter (u: u.type == "openai") upstreamList;
  in
    (optionalAttrs (vllmUpstreams != []) {
      vllm = mkVllmProvider vllmUpstreams;
    })
    // builtins.listToAttrs (map (u: {
        name = u.name;
        value = mkOpenaiProvider [u];
      })
      openaiUpstreams);

  configJson = builtins.toJSON {
    inherit providers;
  };

  bifrostScript = pkgs.writeShellScript "bifrost-launchd-service" ''
    set -euo pipefail
    export HOME="${darwinHomeDir}"

    APP_DIR="${appDir}"
    mkdir -p "$APP_DIR"

    printf '%s\n' ${lib.escapeShellArg configJson} > "$APP_DIR/config.json"

    exec ${pkgs.bifrost-http}/bin/bifrost-http \
      -host ${lib.escapeShellArg cfg.host} \
      -port ${toString cfg.port} \
      -log-level ${lib.escapeShellArg cfg.logLevel} \
      -log-style json \
      -app-dir "$APP_DIR"
  '';
in {
  config = mkIf cfg.enable {
    launchd.daemons.bifrost = {
      serviceConfig = {
        Label = "com.bifrost.service";
        ProgramArguments = ["${bifrostScript}"];
        RunAtLoad = true;
        KeepAlive = true;
        UserName = primaryUser;
        StandardOutPath = "/tmp/bifrost.log";
        StandardErrorPath = "/tmp/bifrost.error.log";
        WorkingDirectory = darwinHomeDir;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          USER = primaryUser;
        };
      };
    };

    system.activationScripts.postActivation.text = mkAfter ''
      mkdir -p "${appDir}"
    '';

    # Register in service registry for port conflict detection and readiness checks
    myConfig.serviceRegistry = optionalAttrs cfg.enable {
      bifrost = {
        name = "Bifrost";
        port = cfg.port;
        launchdLabel = "com.bifrost.service";
        errorLog = "/tmp/bifrost.error.log";
      };
    };
  };
}
