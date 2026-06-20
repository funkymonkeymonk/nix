# vMLX LLM inference server launched service for Darwin (macOS)
# Self-bootstrapping via uv — nixpkgs mlx lacks Metal GPU support,
# so the PyPI wheel (which ships mlx-metal) is required.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.vmlx;

  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "monkey";

  darwinHomeDir = "/Users/${primaryUser}";
  vmlxBin = "${darwinHomeDir}/.local/bin/vmlx";

  resolvedModelPath =
    if cfg.model.package != null
    then "${cfg.model.package}"
    else cfg.model.path;

  escapedModelPath = lib.escapeShellArg resolvedModelPath;

  # Inject Gemma4 chat template if tokenizer_config lacks one.
  # Uses vmlx_engine's bundled gemma4.jinja to avoid re-downloading the model.
  vmlxWrapper = pkgs.writeShellScript "vmlx-bootstrap" ''
    set -e
    if [ ! -x "${vmlxBin}" ]; then
      echo "vMLX not found, installing via uv..." >&2
      HOME=${darwinHomeDir} ${pkgs.uv}/bin/uv tool install vmlx >&2
    fi

    # Check port availability before starting
    PORT=${toString cfg.server.port}
    if lsof -tiTCP -sTCP:LISTEN:"$PORT" -P 2>/dev/null; then
      CONFLICT_PID=$(lsof -tiTCP -sTCP:LISTEN:"$PORT" -P 2>/dev/null | head -1)
      CONFLICT_NAME=$(ps -p "$CONFLICT_PID" -o comm= 2>/dev/null || echo "unknown")
      echo "vMLX: port $PORT is in use by PID $CONFLICT_PID ($CONFLICT_NAME)" >&2
      echo "vMLX: launchd should have stopped the previous instance before starting this one." >&2
      echo "vMLX: The previous process may be stuck in an uninterruptible state (e.g. GPU operation)." >&2
      exit 1
    fi

    exec ${vmlxBin} serve \
      ${escapedModelPath} \
      --host ${lib.escapeShellArg cfg.server.host} \
      --port ${toString cfg.server.port} \
      --continuous-batching \
      --enable-prefix-cache \
      --use-paged-cache \
      --enable-auto-tool-choice \
      --tool-call-parser qwen3 \
      --default-enable-thinking false \
      --max-prompt-tokens ${toString cfg.maxPromptTokens} \
      ${lib.optionalString (cfg.kvCacheQuantization != null) "--kv-cache-quantization ${cfg.kvCacheQuantization}"} \
      ${lib.optionalString cfg.enableDiskCache "--enable-disk-cache"} \
      ${lib.optionalString cfg.enableJIT "--enable-jit"}
  '';
in {
  config = mkIf cfg.enable {
    launchd.daemons.vmlx = {
      serviceConfig = {
        Label = "org.vmlx.server";
        ProgramArguments = ["${vmlxWrapper}"];
        RunAtLoad = true;
        KeepAlive = true;
        ExitTimeOut = 30;
        StandardOutPath = "/tmp/vmlx.log";
        StandardErrorPath = "/tmp/vmlx.err";
        UserName = primaryUser;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${darwinHomeDir}/.local/bin";
        };
      };
    };

    myConfig.serviceRegistry = optionalAttrs cfg.enable {
      vmlx = {
        name = "vMLX";
        port = cfg.server.port;
        launchdLabel = "org.vmlx.server";
        errorLog = "/tmp/vmlx.err";
      };
    };
  };
}
