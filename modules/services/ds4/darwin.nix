# ds4 LLM inference server launched service for Darwin (macOS)
# Runs ds4-server in the foreground, managed by launchd.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.ds4;

  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "monkey";

  darwinHomeDir = "/Users/${primaryUser}";

  resolvedModelPath =
    if cfg.model.package != null
    then "${cfg.model.package}/${cfg.model.gguf}"
    else cfg.model.path;
in {
  config = mkIf cfg.enable {
    launchd.daemons.ds4 = {
      serviceConfig = {
        Label = "org.ds4.server";
        ProgramArguments =
          [
            "${pkgs.ds4}/bin/ds4-server"
            "--host"
            cfg.server.host
            "--port"
            (toString cfg.server.port)
            "--ctx"
            (toString cfg.server.contextSize)
            "--kv-disk-dir"
            "${darwinHomeDir}/.ds4/kv-cache"
            "--kv-disk-space-mb"
            (toString cfg.server.kvDiskSpaceMb)
            "-m"
            resolvedModelPath
          ]
          ++ optional cfg.server.cors "--cors"
          ++ optional (cfg.server.power != null) "--power"
          ++ optional (cfg.server.power != null) (toString cfg.server.power);
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/ds4.log";
        StandardErrorPath = "/tmp/ds4.err";
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          USER = primaryUser;
        };
        WorkingDirectory = "${pkgs.ds4}";
      };
    };
  };
}
