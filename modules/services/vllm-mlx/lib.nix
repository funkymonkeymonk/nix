# Shared helpers for vllm-mlx instance modules.
{
  lib,
  pkgs,
  ...
}: let
  # Resolve a model path to either a Nix store path (if a matching overlay
  # package exists) or the raw HuggingFace ID for runtime download.
  # Model overlay names are derived from the HuggingFace path segment
  # after the org, e.g. mlx-community/gemma-4-26B-A4B-it-OptiQ-4bit
  # -> gemma4-26B-OptiQ-4bit.
  resolveModelPath = path:
    if lib.hasPrefix "/nix/store" path
    then path
    else let
      segments = lib.splitString "/" path;
      modelName = lib.last segments;
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

  # Build the configuration for a single named instance.
  mkInstance = {
    name,
    instanceCfg,
    primaryUser,
    darwinHomeDir,
  }: let
    isDefault = name == "default";
    serviceName =
      if isDefault
      then "vllm-mlx"
      else "vllm-mlx-${name}";
    labelBase =
      if isDefault
      then "org.vllm-mlx"
      else "org.vllm-mlx.${name}";
    appDir = "${darwinHomeDir}/.config/vllm-mlx${lib.optionalString (!isDefault) "/${name}"}";
    logDir =
      if instanceCfg.logDir != null
      then instanceCfg.logDir
      else "${darwinHomeDir}/Library/Logs/vllm-mlx${lib.optionalString (!isDefault) "/${name}"}";

    primaryModelEntry =
      if instanceCfg.mllmDraftModel == null
      then null
      else let
        preloaded = lib.filterAttrs (_: m: m.preload) instanceCfg.models;
        firstPreloaded = lib.head (lib.mapAttrsToList (n: m: {
            name = n;
            value = m;
          })
          preloaded);
        firstModel = lib.head (lib.mapAttrsToList (n: m: {
            name = n;
            value = m;
          })
          instanceCfg.models);
      in
        if preloaded != {}
        then firstPreloaded
        else firstModel;

    primaryModelArg =
      if primaryModelEntry == null
      then ""
      else lib.escapeShellArg (resolveModelPath primaryModelEntry.value.path);

    primaryModelName =
      if primaryModelEntry == null
      then ""
      else primaryModelEntry.name;

    draftKind =
      if instanceCfg.mllmDraftKind != null
      then instanceCfg.mllmDraftKind
      else "mtp";
    draftBlockSize =
      if instanceCfg.mllmDraftBlockSize != null
      then instanceCfg.mllmDraftBlockSize
      else 3;

    registryYaml = let
      modelEntries = lib.mapAttrsToList (modelName: m:
        "  - name: ${modelName}\n"
        + "    path: ${resolveModelPath m.path}\n"
        + "    type: ${m.type}\n"
        + lib.optionalString (m.estimatedMemoryGb != null) "    estimated_memory_gb: ${toString m.estimatedMemoryGb}\n"
        + lib.optionalString m.preload "    preload: true\n"
        + lib.optionalString (m.type == "lm") "    mllm: false\n")
      instanceCfg.models;
      yamlContent = lib.concatStringsSep "\n" ([
          "manager:"
          "  memory_budget_gb: ${toString instanceCfg.memoryBudgetGb}"
          "  contention_policy:"
          "    strategy: ${instanceCfg.contention}"
          ""
          "models:"
        ]
        ++ modelEntries);
    in
      pkgs.writeText "vllm-mlx-${name}-registry.yaml" yamlContent;

    vllmMlxWrapper = pkgs.writeShellScript "${serviceName}-launchd-service" ''
      set -euo pipefail
      export HOME="${darwinHomeDir}"

      APP_DIR="${appDir}"
      mkdir -p "$APP_DIR"
      mkdir -p ${logDir}

      cat ${registryYaml} > "$APP_DIR/registry.yaml"

      PORT=${toString instanceCfg.server.port}
      if lsof -tiTCP -sTCP:LISTEN:"$PORT" -P 2>/dev/null; then
        CONFLICT_PID=$(lsof -tiTCP -sTCP:LISTEN:"$PORT" -P 2>/dev/null | head -1)
        CONFLICT_NAME=$(ps -p "$CONFLICT_PID" -o comm= 2>/dev/null || echo "unknown")
        echo "${serviceName}: port $PORT is in use by PID $CONFLICT_PID ($CONFLICT_NAME)" >&2
        echo "${serviceName}: launchd should have stopped the previous instance before starting this one." >&2
        exit 1
      fi

      exec ${
        if instanceCfg.package != null
        then lib.escapeShellArg instanceCfg.package
        else "${pkgs.vllm-mlx}/bin/vllm-mlx"
      } serve \
        ${
        if instanceCfg.mllmDraftModel != null
        then primaryModelArg
        else "--models-config \"$APP_DIR/registry.yaml\""
      } \
        ${lib.optionalString (instanceCfg.mllmDraftModel != null) "--served-model-name ${lib.escapeShellArg primaryModelName}"} \
        --host ${lib.escapeShellArg instanceCfg.server.host} \
        --port ${toString instanceCfg.server.port} \
        --timeout ${toString instanceCfg.timeout} \
        --use-paged-cache \
        ${lib.optionalString instanceCfg.enableAutoToolChoice "--enable-auto-tool-choice"} \
        ${lib.optionalString (instanceCfg.toolCallParser != null) "--tool-call-parser ${instanceCfg.toolCallParser}"} \
        ${lib.optionalString (instanceCfg.reasoningParser != null) "--reasoning-parser ${instanceCfg.reasoningParser}"} \
        ${lib.optionalString (instanceCfg.maxKvSize != null) "--max-kv-size ${toString instanceCfg.maxKvSize}"} \
        ${lib.optionalString instanceCfg.enableMetrics "--enable-metrics"} \
        ${lib.optionalString instanceCfg.enableContinuousBatching "--continuous-batching"} \
        ${lib.optionalString instanceCfg.enablePrefixCache "--enable-prefix-cache"} \
        ${lib.optionalString (instanceCfg.chunkedPrefillTokens != null) "--chunked-prefill-tokens ${toString instanceCfg.chunkedPrefillTokens}"} \
        ${lib.optionalString instanceCfg.enableMtp "--enable-mtp"} \
        ${lib.optionalString instanceCfg.enableMtp "--mtp-num-draft-tokens ${toString instanceCfg.mtpNumDraftTokens}"} \
        ${lib.optionalString (instanceCfg.enableMtp && instanceCfg.mtpOptimistic) "--mtp-optimistic"} \
        ${lib.optionalString (instanceCfg.mllmDraftModel != null) "--mllm-draft-model ${lib.escapeShellArg (resolveModelPath instanceCfg.mllmDraftModel)}"} \
        ${lib.optionalString (instanceCfg.mllmDraftModel != null) "--mllm-draft-kind ${draftKind}"} \
        ${lib.optionalString (instanceCfg.mllmDraftModel != null) "--mllm-draft-block-size ${toString draftBlockSize}"}
    '';

    vllmMlxWarmup = pkgs.writeShellScript "${serviceName}-warmup" ''
      set -euo pipefail
      HOST="${lib.escapeShellArg instanceCfg.server.host}"
      PORT=${toString instanceCfg.server.port}
      MAX_WAIT=300

      echo "Waiting for ${serviceName} on $HOST:$PORT..."
      for i in $(seq 1 $MAX_WAIT); do
        if ${pkgs.curl}/bin/curl -sf "http://$HOST:$PORT/v1/models" >/dev/null 2>&1; then
          echo "${serviceName} is ready"
          break
        fi
        sleep 1
      done

      if [ $i -eq $MAX_WAIT ]; then
        echo "Timeout waiting for ${serviceName}"
        exit 1
      fi

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (modelName: _m: ''
          echo "Warming up ${modelName}..."
          ${pkgs.curl}/bin/curl -sf "http://$HOST:$PORT/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d '{"model":"${modelName}","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
            >/dev/null 2>&1 || echo "  ${modelName} warmup failed (may need more time)"
        '')
        instanceCfg.models)}

      echo "Warmup complete"
    '';
  in {
    launchd.daemons.${serviceName} = {
      command = vllmMlxWrapper;
      serviceConfig = {
        Label = "${labelBase}.server";
        RunAtLoad = true;
        KeepAlive = true;
        ExitTimeOut = 30;
        StandardOutPath = "${logDir}/server.log";
        StandardErrorPath = "${logDir}/server.error.log";
        UserName = primaryUser;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
          VLLM_MLX_SIMPLE_ENGINE_LOCK_ADMISSION = instanceCfg.lockAdmission;
        };
      };
    };

    launchd.daemons."${serviceName}-warmup" = {
      command = vllmMlxWarmup;
      serviceConfig = {
        Label = "${labelBase}.warmup";
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

    myConfig.serviceRegistry = (import ../../common/lib.nix {inherit lib;}).mkServiceRegistry serviceName {
      displayName = serviceName;
      port = instanceCfg.server.port;
      label = "${labelBase}.server";
      errorLog = "${logDir}/server.error.log";
      enabled = instanceCfg.enable;
    };
  };
in {
  inherit resolveModelPath mkInstance;
}
