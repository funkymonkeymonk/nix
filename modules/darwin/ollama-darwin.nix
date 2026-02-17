{
  lib,
  pkgs,
  config,
  ...
}: {
  options.services.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM server";

    acceleration = lib.mkOption {
      type = lib.types.enum ["metal" "cpu"];
      default = "metal";
      description = "Hardware acceleration type";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host to bind to";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port to listen on";
    };

    modelsDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ollama";
      description = "Directory for model storage";
    };

    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Models to preload on startup";
    };
  };

  config = let
    cfg = config.services.ollama;
  in
    lib.mkIf cfg.enable {
      environment.systemPackages = [pkgs.ollama];

      launchd.daemons.ollama = {
        serviceConfig = {
          Label = "com.ollama.service";
          ProgramArguments = [
            "${pkgs.ollama}/bin/ollama"
            "serve"
          ];
          EnvironmentVariables =
            {
              OLLAMA_HOST = "${cfg.host}:${toString cfg.port}";
              OLLAMA_MODELS = cfg.modelsDir;
            }
            // (lib.optionalAttrs (cfg.acceleration == "metal") {
              OLLAMA_VISIBLE_DEVICES = "all";
            });
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "/var/log/ollama.log";
          StandardErrorPath = "/var/log/ollama.log";
        };
      };

      system.activationScripts.ollama-models = {
        text = ''
          mkdir -p ${cfg.modelsDir}
        '';
      };
    };
}
