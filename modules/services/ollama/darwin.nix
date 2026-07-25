# Ollama service module for Darwin (macOS)
#
# Uses launchd to manage Ollama as a system daemon.
# Ollama is installed via homebrew — no nixpkgs dependency.
{
  config,
  lib,
  options,
  ...
}:
with lib; let
  cfg = config.myConfig.ollama;
  hasHomebrew = builtins.hasAttr "homebrew" options;

  commonLib = import ../../common/lib.nix {inherit lib;};

  primaryUser = commonLib.primaryUser config;
  darwinHomeDir = commonLib.darwinHomeDir config;
in {
  options.myConfig.ollama = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Ollama inference server for local LLMs";
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Bind address for Ollama server";
    };

    port = mkOption {
      type = types.port;
      default = 11434;
      description = "Bind port for Ollama server";
    };

    keepAlive = mkOption {
      type = types.str;
      default = "8h";
      description = "Duration to keep loaded models in memory (e.g. \"8h\", \"24h\", \"0\" for infinite)";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (optionalAttrs hasHomebrew {
      homebrew.brews = ["ollama"];
    })
    {
      launchd.daemons.ollama = {
        command = "ollama serve";
        serviceConfig = {
          Label = "org.ollama.server";
          RunAtLoad = true;
          KeepAlive = true;
          StandardOutPath = "/tmp/ollama.log";
          StandardErrorPath = "/tmp/ollama.err";
          UserName = primaryUser;
          EnvironmentVariables = {
            HOME = darwinHomeDir;
            OLLAMA_HOST = "${cfg.host}:${toString cfg.port}";
            OLLAMA_KEEPALIVE = "${cfg.keepAlive}";
            PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin";
          };
        };
      };

      system.activationScripts.postActivation.text = mkAfter ''
        mkdir -p "${darwinHomeDir}/.ollama"
      '';

      myConfig.serviceRegistry = commonLib.mkServiceRegistry "ollama" {
        displayName = "Ollama";
        port = cfg.port;
        label = "org.ollama.server";
        errorLog = "/tmp/ollama.err";
        enabled = cfg.enable;
      };
    }
  ]);
}
