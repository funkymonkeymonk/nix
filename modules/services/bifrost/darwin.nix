# Bifrost AI gateway launched service for Darwin (macOS)
# Runs bifrost-http as a foreground process, managed by launchd.
# Bifrost proxies all AI requests to upstream inference servers (vMLX, ds4, etc.)
# and exposes them through a single OpenAI-compatible API.
#
# The Bifrost web UI (request tracing, log streaming, token analytics) is
# served at the root path on the same port as the API.  Default location:
#   http://localhost:8081/
# Prometheus metrics: http://localhost:8081/metrics
# OpenAI-compatible API: http://localhost:8081/v1/
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.bifrost;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
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

  mkNetworkConfig = upstream: {
    allow_private_network = upstream.allowPrivateNetwork;
    default_request_timeout_in_seconds = upstream.requestTimeout;
    stream_idle_timeout_in_seconds = upstream.streamIdleTimeoutInSeconds;
    max_retries = upstream.maxRetries;
    retry_backoff_initial = "${toString upstream.retryBackoffInitialMs}ms";
    retry_backoff_max = "${toString upstream.retryBackoffMaxMs}ms";
  };

  mkProvider = baseProviderType: upstreams: {
    keys = map mkOpenaiProviderKey upstreams;
    network_config =
      (mkNetworkConfig (builtins.head upstreams))
      // {
        base_url = (builtins.head upstreams).url;
      };
    custom_provider_config = {
      base_provider_type = baseProviderType;
      allowed_requests = {
        list_models = true;
        chat_completion = true;
        chat_completion_stream = true;
        responses = baseProviderType == "anthropic";
        responses_stream = baseProviderType == "anthropic";
        embedding = true;
      };
      request_path_overrides =
        if baseProviderType == "openai"
        then {
          chat_completion = "/v1/chat/completions";
          chat_completion_stream = "/v1/chat/completions";
          embedding = "/v1/embeddings";
        }
        else {};
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
    network_config = mkNetworkConfig firstUpstream;
  };

  providers = let
    vllmUpstreams = filter (u: u.type == "vllm") upstreamList;
    openaiUpstreams = filter (u: u.type == "openai") upstreamList;
    anthropicUpstreams = filter (u: u.type == "anthropic") upstreamList;
  in
    (optionalAttrs (vllmUpstreams != []) {
      vllm = mkVllmProvider vllmUpstreams;
    })
    // builtins.listToAttrs (map (u: {
        name = u.name;
        value = mkProvider "openai" [u];
      })
      openaiUpstreams)
    // builtins.listToAttrs (map (u: {
        name = u.name;
        value = mkProvider "anthropic" [u];
      })
      anthropicUpstreams);

  configJson = builtins.toJSON {
    inherit providers;
  };

  bifrostScript = pkgs.writeShellScript "bifrost-launchd-service" ''
    set -euo pipefail
    export HOME="${darwinHomeDir}"

    APP_DIR="${appDir}"
    mkdir -p "$APP_DIR"

    printf '%s\n' ${lib.escapeShellArg configJson} > "$APP_DIR/config.json"

    # Check port availability before starting
    PORT=${toString cfg.port}
    if lsof -tiTCP -sTCP:LISTEN:"$PORT" -P 2>/dev/null; then
      CONFLICT_PID=$(lsof -tiTCP -sTCP:LISTEN:"$PORT" -P 2>/dev/null | head -1)
      CONFLICT_NAME=$(ps -p "$CONFLICT_PID" -o comm= 2>/dev/null || echo "unknown")
      echo "Bifrost: port $PORT is in use by PID $CONFLICT_PID ($CONFLICT_NAME)" >&2
      echo "Bifrost: launchd should have stopped the previous instance before starting this one." >&2
      echo "Bifrost: The previous process may be stuck in an uninterruptible state (e.g. GPU operation)." >&2
      exit 1
    fi

    exec ${pkgs.bifrost-http}/bin/bifrost-http \
      -host ${lib.escapeShellArg cfg.host} \
      -port ${toString cfg.port} \
      -log-level ${lib.escapeShellArg cfg.logLevel} \
      -log-style json \
      -app-dir "$APP_DIR"
  '';
in {
  options.myConfig.bifrost = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Bifrost AI gateway for unified LLM access across all local inference servers";
    };

    port = mkOption {
      type = types.port;
      default = 8081;
      description = "Port for Bifrost HTTP gateway";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Host to bind Bifrost to";
    };

    logLevel = mkOption {
      type = types.enum ["debug" "info" "warn" "error"];
      default = "info";
      description = "Bifrost log level";
    };

    appDir = mkOption {
      type = types.str;
      default = "$HOME/.config/bifrost";
      description = "Directory for Bifrost data (config.json, SQLite DB, request logs)";
    };

    upstreams = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          url = mkOption {
            type = types.str;
            description = "Base URL for the upstream inference server (e.g., http://localhost:8300/v1)";
          };
          type = mkOption {
            type = types.enum ["openai" "anthropic" "vllm"];
            default = "openai";
            description = "Provider type for the upstream. Use 'openai' or 'anthropic' for compatible APIs, or 'vllm' for Bifrost's native vLLM integration";
          };
          apiKey = mkOption {
            type = types.str;
            default = "dummy";
            description = "API key for the upstream (dummy for local servers)";
          };
          allowPrivateNetwork = mkOption {
            type = types.bool;
            default = true;
            description = "Allow connecting to private network IPs (localhost, 192.168.x.x, 10.x.x.x)";
          };
          requestTimeout = mkOption {
            type = types.ints.unsigned;
            default = 120;
            description = "Default request timeout in seconds";
          };
          maxRetries = mkOption {
            type = types.ints.unsigned;
            default = 0;
            description = "Maximum retry attempts for retryable upstream errors (e.g. 503 from a busy local engine). Bifrost's stock default is 0 — a single attempt — so transient failures fail the whole request. Local agent gateways should set 2-3.";
          };
          retryBackoffInitialMs = mkOption {
            type = types.ints.positive;
            default = 500;
            description = "Initial retry backoff in milliseconds (matches Bifrost's upstream default of 500ms). Retries back off exponentially up to retryBackoffMaxMs.";
          };
          retryBackoffMaxMs = mkOption {
            type = types.ints.positive;
            default = 5000;
            description = "Maximum retry backoff in milliseconds (matches Bifrost's upstream default of 5s).";
          };
          streamIdleTimeoutInSeconds = mkOption {
            type = types.ints.unsigned;
            default = 60;
            description = ''
              Idle timeout for streaming responses. If no chunk arrives from the
              upstream within this window, Bifrost closes the connection.
               Must be >= the upstream's longest prefill time. For oMLX with
              long system prompts (22k+ tokens), set to 600s to avoid 500 errors
              during chunked prefill. Bifrost default is 60s.
            '';
          };
          models = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Model names to expose via this upstream (empty = wildcard). For vllm provider, list the models available on the vLLM server";
          };
        };
      });
      default = {};
      description = "Upstream model servers to proxy through Bifrost. Each key becomes the provider prefix for model routing (e.g., 'omlx' → model 'omlx/qwen3.8-27b')";
    };
  };

  config = mkIf cfg.enable {
    launchd.daemons.bifrost = {
      command = bifrostScript;
      serviceConfig = {
        Label = "com.bifrost.service";
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
    myConfig.serviceRegistry = commonLib.mkServiceRegistry "bifrost" {
      displayName = "Bifrost";
      port = cfg.port;
      label = "com.bifrost.service";
      errorLog = "/tmp/bifrost.error.log";
      enabled = cfg.enable;
    };
  };
}
