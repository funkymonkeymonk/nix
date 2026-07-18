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
      #   gemma4-31B-4bit  -> mlx-community/gemma-4-31b-it-4bit
      #   gemma4-e4B-4bit  -> mlx-community/gemma-4-e4b-it-4bit
      overlayName =
        if modelName == "gemma-4-31b-it-4bit"
        then "gemma4-31B-4bit"
        else if modelName == "gemma-4-e4b-it-4bit"
        then "gemma4-e4B-4bit"
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
      ${lib.optionalString (cfg.maxKvSize != null) "--max-kv-size ${toString cfg.maxKvSize}"}
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
  config = lib.mkIf cfg.enable {
    launchd.daemons.vllm-mlx = {
      command = vllmMlxWrapper;
      serviceConfig = {
        Label = "org.vllm-mlx.server";
        RunAtLoad = true;
        KeepAlive = true;
        ExitTimeOut = 30;
        StandardOutPath = "/tmp/vllm-mlx.log";
        StandardErrorPath = "/tmp/vllm-mlx.err";
        UserName = primaryUser;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
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
        StandardOutPath = "/tmp/vllm-mlx-warmup.log";
        StandardErrorPath = "/tmp/vllm-mlx-warmup.err";
        UserName = primaryUser;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
        };
      };
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      mkdir -p "${appDir}"
    '';

    myConfig.serviceRegistry = commonLib.mkServiceRegistry "vllm-mlx" {
      displayName = "vllm-mlx";
      port = cfg.server.port;
      label = "org.vllm-mlx.server";
      errorLog = "/tmp/vllm-mlx.err";
      enabled = cfg.enable;
    };
  };
}
