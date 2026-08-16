# vllm-mlx inference server launched service for Darwin (macOS)
# Uses the Nix-packaged vllm-mlx binary (no runtime uv install).
# Supports pre-downloaded models via pkgs.mlx-models overlays.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.vllmMlx;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
  appDir = "${darwinHomeDir}/.config/vllm-mlx";

  # Durable log location. /tmp is cleaned by macOS every 3 days; launchd
  # keeps writing to the deleted inode and all server output is lost.
  logDir =
    if cfg.logDir != null
    then cfg.logDir
    else "${darwinHomeDir}/Library/Logs/vllm-mlx";

  # Resolve a model path to either a Nix store path (if a matching overlay
  # package exists) or the raw HuggingFace ID for runtime download.
  # Model overlay names are derived from the HuggingFace path segment
  # after the org, e.g. mlx-community/gemma-4-26B-A4B-it-OptiQ-4bit
  # -> gemma4-26B-OptiQ-4bit.
  resolveModelPath = path:
    if lib.hasPrefix "/nix/store" path
    then path
    else let
      # Strip org prefix, keep last segment
      segments = lib.splitString "/" path;
      modelName = lib.last segments;
      # Convert HF name to overlay-style name.
      # Known overlays in this repo:
      #   gemma4-31B-4bit      -> mlx-community/gemma-4-31b-it-4bit
      #   gemma4-e4B-4bit      -> mlx-community/gemma-4-e4b-it-4bit
      #   qwen3_8-27B-8bit     -> mlx-community/Qwen3.8-27B-8bit
      #   qwen3_8-27B-MTP-8bit -> mlx-community/Qwen3.8-27B-MTP-8bit
      #   qwen3_8-27B-MTP-4bit -> mlx-community/Qwen3.8-27B-MTP-4bit
      overlayName =
        if modelName == "gemma-4-31b-it-4bit"
        then "gemma4-31B-4bit"
        else if modelName == "gemma-4-e4b-it-4bit"
        then "gemma4-e4B-4bit"
        else if modelName == "Qwen3.8-27B-8bit"
        then "qwen3_8-27B-8bit"
        else if modelName == "Qwen3.8-27B-4bit"
        then "qwen3_8-27B-4bit"
        else if modelName == "Qwen3.8-27B-MTP-8bit"
        then "qwen3_8-27B-MTP-8bit"
        else if modelName == "Qwen3.8-27B-MTP-4bit"
        then "qwen3_8-27B-MTP-4bit"
        else null;
    in
      if overlayName != null && pkgs ? ${overlayName}
      then "${pkgs.${overlayName}}"
      else path;

  # Build model registry YAML from Nix attrset
  # vllm-mlx expects models as a YAML list, not a map
  registryYaml = let
    modelEntries = lib.mapAttrsToList (name: m:
      "  - name: ${name}\n"
      + "    path: ${resolveModelPath m.path}\n"
      + "    type: ${m.type}\n"
      + lib.optionalString (m.estimatedMemoryGb != null) "    estimated_memory_gb: ${toString m.estimatedMemoryGb}\n"
      + lib.optionalString m.preload "    preload: true\n"
      + lib.optionalString (m.type == "lm") "    mllm: false\n")
    cfg.models;
    yamlContent = lib.concatStringsSep "\n" ([
        "manager:"
        "  memory_budget_gb: ${toString cfg.memoryBudgetGb}"
        "  contention_policy:"
        "    strategy: ${cfg.contention}"
        ""
        "models:"
      ]
      ++ modelEntries);
  in
    pkgs.writeText "vllm-mlx-registry.yaml" yamlContent;

  vllmMlxWrapper = pkgs.writeShellScript "vllm-mlx-launchd-service" ''
    set -euo pipefail
    export HOME="${darwinHomeDir}"

    APP_DIR="${appDir}"
    mkdir -p "$APP_DIR"
    mkdir -p ${logDir}

    # Copy registry into writable location
    cat ${registryYaml} > "$APP_DIR/registry.yaml"

    # Check port availability before starting
    PORT=${toString cfg.server.port}
    if lsof -tiTCP -sTCP:LISTEN:"$PORT" -P 2>/dev/null; then
      CONFLICT_PID=$(lsof -tiTCP -sTCP:LISTEN:"$PORT" -P 2>/dev/null | head -1)
      CONFLICT_NAME=$(ps -p "$CONFLICT_PID" -o comm= 2>/dev/null || echo "unknown")
      echo "vllm-mlx: port $PORT is in use by PID $CONFLICT_PID ($CONFLICT_NAME)" >&2
      echo "vllm-mlx: launchd should have stopped the previous instance before starting this one." >&2
      exit 1
    fi

    exec ${
      if cfg.package != null
      then lib.escapeShellArg cfg.package
      else "${pkgs.vllm-mlx}/bin/vllm-mlx"
    } serve \
      --models-config "$APP_DIR/registry.yaml" \
      --host ${lib.escapeShellArg cfg.server.host} \
      --port ${toString cfg.server.port} \
      --timeout ${toString cfg.timeout} \
      --use-paged-cache \
      ${lib.optionalString cfg.enableAutoToolChoice "--enable-auto-tool-choice"} \
      ${lib.optionalString (cfg.toolCallParser != null) "--tool-call-parser ${cfg.toolCallParser}"} \
      ${lib.optionalString (cfg.reasoningParser != null) "--reasoning-parser ${cfg.reasoningParser}"} \
      ${lib.optionalString (cfg.maxKvSize != null) "--max-kv-size ${toString cfg.maxKvSize}"} \
      ${lib.optionalString cfg.enableMetrics "--enable-metrics"} \
      ${lib.optionalString cfg.enableContinuousBatching "--continuous-batching"} \
      ${lib.optionalString cfg.enablePrefixCache "--enable-prefix-cache"} \
      ${lib.optionalString (cfg.chunkedPrefillTokens != null) "--chunked-prefill-tokens ${toString cfg.chunkedPrefillTokens}"} \
      ${lib.optionalString cfg.enableMtp "--enable-mtp"} \
      ${lib.optionalString cfg.enableMtp "--mtp-num-draft-tokens ${toString cfg.mtpNumDraftTokens}"} \
      ${lib.optionalString (cfg.enableMtp && cfg.mtpOptimistic) "--mtp-optimistic"} \
      ${lib.optionalString (cfg.mllmDraftModel != null) "--mllm-draft-model ${lib.escapeShellArg (resolveModelPath cfg.mllmDraftModel)}"} \
      ${lib.optionalString (cfg.mllmDraftModel != null && cfg.mllmDraftKind != null) "--mllm-draft-kind ${cfg.mllmDraftKind}"} \
      ${lib.optionalString (cfg.mllmDraftModel != null && cfg.mllmDraftBlockSize != null) "--mllm-draft-block-size ${toString cfg.mllmDraftBlockSize}"}
  '';

  # Warmup script: pre-load model weights into memory after service start
  vllmMlxWarmup = pkgs.writeShellScript "vllm-mlx-warmup" ''
    set -euo pipefail
    HOST="${lib.escapeShellArg cfg.server.host}"
    PORT=${toString cfg.server.port}
    MAX_WAIT=300

    echo "Waiting for vllm-mlx on $HOST:$PORT..."
    for i in $(seq 1 $MAX_WAIT); do
      if ${pkgs.curl}/bin/curl -sf "http://$HOST:$PORT/v1/models" >/dev/null 2>&1; then
        echo "vllm-mlx is ready"
        break
      fi
      sleep 1
    done

    if [ $i -eq $MAX_WAIT ]; then
      echo "Timeout waiting for vllm-mlx"
      exit 1
    fi

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: _m: ''
        echo "Warming up ${name}..."
        ${pkgs.curl}/bin/curl -sf "http://$HOST:$PORT/v1/chat/completions" \
          -H "Content-Type: application/json" \
          -d '{"model":"${name}","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
          >/dev/null 2>&1 || echo "  ${name} warmup failed (may need more time)"
      '')
      cfg.models)}

    echo "Warmup complete"
  '';
in {
  options.myConfig.vllmMlx = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable vllm-mlx inference server for local MLX models (OpenAI + Anthropic API with multi-model hotswap)";
    };

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Override the vllm-mlx binary path. When null, uses the Nix-packaged vllm-mlx (built with Metal GPU support via prebuilt PyPI wheels). Set to an external binary (e.g. uv-installed) only for testing upstream fixes or when the Nix package version is too old.";
    };

    server = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Bind address for vllm-mlx server";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8300;
        description = "Bind port for vllm-mlx server";
      };
    };

    memoryBudgetGb = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 24;
      description = "Memory budget in GB for model loading. Idle models are evicted under this budget.";
    };

    contention = lib.mkOption {
      type = lib.types.enum ["wait" "preempt" "fail"];
      default = "preempt";
      description = "Behavior when a requested model is not loaded and memory is full: wait (queue), preempt (evict current), or fail (reject).";
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "Model path or HuggingFace ID (e.g., mlx-community/gemma-4-12B-it-qat-4bit)";
          };
          type = lib.mkOption {
            type = lib.types.enum ["lm" "multimodal" "embedding"];
            default = "lm";
            description = "Model type: lm (text), multimodal (vision), or embedding";
          };
          estimatedMemoryGb = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            description = "Estimated memory in GB for non-local (HuggingFace) models. Required for registry-backed loading so eviction remains deterministic.";
          };
          preload = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Load this model into memory at server startup. Useful for keeping frequently-used models resident.";
          };
        };
      });
      default = {};
      description = "Model registry. Each key is a model alias used in API requests. vllm-mlx lazily loads models on first use.";
    };

    enableAutoToolChoice = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable automatic tool calling. The model decides when to use tools based on the prompt.";
    };

    toolCallParser = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["auto" "mistral" "qwen" "qwen3_coder" "llama" "hermes" "harmony" "gpt-oss" "deepseek" "kimi" "granite" "nemotron" "xlam" "functionary" "gemma4" "glm47" "minimax"]);
      default = null;
      description = "Tool call parser format. Must match model's training format. 'gemma4' for Gemma 4, 'qwen' for Qwen2/3.";
    };

    reasoningParser = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["qwen3" "deepseek_r1" "gpt_oss" "harmony" "gemma4" "glm4" "mistral" "poolside_v1"]);
      default = null;
      description = "Reasoning parser for extracting thinking/reasoning content from model output. 'qwen3' for Qwen3, 'gemma4' for Gemma 4.";
    };

    lockAdmission = lib.mkOption {
      type = lib.types.enum ["wait" "fail_fast"];
      default = "wait";
      description = "Admission policy when a request arrives while another generation holds the serialized engine lock. 'wait' queues requests (correct for a single-user local server behind agent traffic, where parallel requests are normal); 'fail_fast' rejects with 503 text_generation_busy. Maps to VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION.";
    };

    logDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Directory for launchd stdout/stderr logs. Defaults to ~/Library/Logs/vllm-mlx for the primary user. Do not use /tmp: macOS cleans it every 3 days and launchd keeps writing to the deleted inode, silently discarding all server logs.";
    };

    maxKvSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "Maximum KV cache size per sequence (number of tokens). When set, oldest tokens roll off to prevent unbounded memory growth.";
    };

    timeout = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 120;
      description = "Request timeout in seconds.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum ["DEBUG" "INFO" "WARNING" "ERROR"];
      default = "INFO";
      description = "Server log level.";
    };

    enableMetrics = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Expose Prometheus metrics on /metrics endpoint.";
    };

    enableContinuousBatching = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable continuous batching (BatchedEngine) for concurrent requests. Allows prefix caching across turns but adds per-request overhead.";
    };

    enablePrefixCache = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable prefix caching in BatchedEngine mode. Reuses KV cache blocks for common prompt prefixes across requests/conversations. Requires --continuous-batching.";
    };

    chunkedPrefillTokens = lib.mkOption {
      type = lib.types.nullOr (lib.types.addCheck lib.types.int (x: x >= 0));
      default = null;
      description = "Chunk size for prefill processing in BatchedEngine mode (0 disables chunked prefill). May be needed to avoid crashes with large prompts when prefix caching is enabled.";
    };

    enableMtp = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Multi-Token Prediction (MTP) for models with built-in MTP heads such as Qwen3.8. Can significantly increase generation throughput.";
    };

    mtpNumDraftTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Number of draft tokens to predict per MTP step. Higher values increase speed when acceptance rate is high.";
    };

    mtpOptimistic = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip MTP acceptance verification for maximum speed. May produce ~5-10% incorrect tokens; use with caution.";
    };

    mllmDraftModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path or HuggingFace repo ID of an mlx-vlm MLLM draft/assistant model.
        Used for speculative decoding with --mllm-draft-kind. For example, the
        Qwen3.8-27B-MTP-8bit drafter weights are used alongside a compatible
        Qwen3.8 27B target checkpoint; they are not a standalone model.
      '';
    };

    mllmDraftKind = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["mtp"]);
      default =
        if cfg.mllmDraftModel != null
        then "mtp"
        else null;
      description = "mlx-vlm draft kind for --mllm-draft-model. Only 'mtp' is supported.";
    };

    mllmDraftBlockSize = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default =
        if cfg.mllmDraftModel != null
        then 3
        else null;
      description = "Draft block size passed to mlx-vlm for --mllm-draft-model.";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.daemons.vllm-mlx = {
      command = vllmMlxWrapper;
      serviceConfig = {
        Label = "org.vllm-mlx.server";
        RunAtLoad = true;
        KeepAlive = true;
        ExitTimeOut = 30;
        StandardOutPath = "${logDir}/server.log";
        StandardErrorPath = "${logDir}/server.error.log";
        UserName = primaryUser;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
          VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION = cfg.lockAdmission;
        };
      };
    };

    launchd.daemons.vllm-mlx-warmup = {
      command = vllmMlxWarmup;
      serviceConfig = {
        Label = "org.vllm-mlx.warmup";
        RunAtLoad = true;
        KeepAlive = false;
        ExitTimeOut = 600;
        StandardOutPath = "${logDir}/warmup.log";
        StandardErrorPath = "${logDir}/warmup.error.log";
        UserName = primaryUser;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
        };
      };
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      mkdir -p "${appDir}" "${logDir}"
    '';

    myConfig.serviceRegistry = commonLib.mkServiceRegistry "vllm-mlx" {
      displayName = "vllm-mlx";
      port = cfg.server.port;
      label = "org.vllm-mlx.server";
      errorLog = "${logDir}/server.error.log";
      enabled = cfg.enable;
    };
  };
}
