# vllm-mlx inference server launched service for Darwin (macOS)
# Self-bootstrapping via uv — nixpkgs lacks vllm-mlx package.
# vllm-mlx supports multi-model registry, continuous batching,
# and OpenAI + Anthropic APIs with proper Gemma 4 tool parsing.
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
  vllmMlxBin = "${darwinHomeDir}/.local/bin/vllm-mlx";
  appDir = "${darwinHomeDir}/.config/vllm-mlx";

  # Build model registry YAML from Nix attrset
  # vllm-mlx expects models as a YAML list, not a map
  registryYaml = let
    modelEntries = lib.mapAttrsToList (name: m:
      "  - name: ${name}\n"
      + "    path: ${m.path}\n"
      + "    type: ${m.type}\n"
      + lib.optionalString (m.estimatedMemoryGb != null) "    estimated_memory_gb: ${toString m.estimatedMemoryGb}\n")
    cfg.models;
    yamlContent = lib.concatStringsSep "\n" ([
        "manager:"
        "  memory_budget_gb: ${toString cfg.memoryBudgetGb}"
        "  contention: ${cfg.contention}"
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

    if [ ! -x "${vllmMlxBin}" ]; then
      echo "vllm-mlx not found, installing via uv..." >&2
      HOME=${darwinHomeDir} ${pkgs.uv}/bin/uv tool install vllm-mlx >&2
    fi

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

    exec ${vllmMlxBin} serve \
      --models-config "$APP_DIR/registry.yaml" \
      --host ${lib.escapeShellArg cfg.server.host} \
      --port ${toString cfg.server.port} \
      --timeout ${toString cfg.timeout} \
      ${lib.optionalString cfg.enableAutoToolChoice "--enable-auto-tool-choice"} \
      ${lib.optionalString (cfg.toolCallParser != null) "--tool-call-parser ${cfg.toolCallParser}"}
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
          PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${darwinHomeDir}/.local/bin";
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
