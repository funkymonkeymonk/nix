# Ollama service module for Darwin (macOS)
#
# Uses launchd to manage Ollama as a system daemon.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.ollama;

  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "monkey";

  darwinHomeDir = "/Users/${primaryUser}";
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.ollama];

    launchd.daemons.ollama = {
      command = "${pkgs.ollama}/bin/ollama serve";
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
        };
      };
    };

    system.activationScripts.postActivation.text = mkAfter ''
      mkdir -p "${darwinHomeDir}/.ollama"
    '';

    myConfig.serviceRegistry = optionalAttrs cfg.enable {
      ollama = {
        name = "Ollama";
        port = cfg.port;
        launchdLabel = "org.ollama.server";
        errorLog = "/tmp/ollama.err";
      };
    };
  };
}
