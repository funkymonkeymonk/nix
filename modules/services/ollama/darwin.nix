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
            OLLAMA_KEEPALIVE = "8h";
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
