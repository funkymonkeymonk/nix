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

  vmlxWrapper = pkgs.writeShellScript "vmlx-bootstrap" ''
    set -e
    if [ ! -x "${vmlxBin}" ]; then
      echo "vMLX not found, installing via uv..." >&2
      HOME=${darwinHomeDir} ${pkgs.uv}/bin/uv tool install vmlx >&2
    fi

    MODEL_DIR=${escapedModelPath}
    TEMPLATE_FILE="$(${pkgs.python3}/bin/python3 -c "
    import vmlx_engine.chat_templates, os
    d = os.path.dirname(vmlx_engine.chat_templates.__file__)
    print(os.path.join(d, 'gemma4.jinja'))
    " 2>/dev/null || echo '')"

    if [ -n "$TEMPLATE_FILE" ] && [ -f "$TEMPLATE_FILE" ] && [ -f "$MODEL_DIR/tokenizer_config.json" ]; then
      if ! ${pkgs.python3}/bin/python3 -c "import json; json.load(open('$MODEL_DIR/tokenizer_config.json')).get('chat_template')" 2>/dev/null; then
        echo "Injecting chat template from $TEMPLATE_FILE" >&2
        ${pkgs.python3}/bin/python3 -c "
import json
with open('$TEMPLATE_FILE') as f:
    tmpl = f.read()
with open('$MODEL_DIR/tokenizer_config.json') as f:
    cfg = json.load(f)
cfg['chat_template'] = tmpl
with open('$MODEL_DIR/tokenizer_config.json', 'w') as f:
    json.dump(cfg, f, indent=2)
print('Chat template injected')
"
      fi
    fi

    exec ${vmlxBin} serve \
      ${escapedModelPath} \
      --host ${lib.escapeShellArg cfg.server.host} \
      --port ${toString cfg.server.port} \
      --continuous-batching \
      --enable-prefix-cache \
      --use-paged-cache \
      --enable-auto-tool-choice \
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
        StandardOutPath = "/tmp/vmlx.log";
        StandardErrorPath = "/tmp/vmlx.err";
        UserName = primaryUser;
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${darwinHomeDir}/.local/bin";
        };
      };
    };
  };
}
