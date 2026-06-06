# Higgs LLM inference server launchd service for Darwin (macOS)
# Runs higgs serve in the foreground, managed by launchd.
# Config is managed via home-manager (~/.config/higgs/config.toml).
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.higgs;

  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "higgs";

  darwinHomeDir = "/Users/${primaryUser}";
in {
  config = mkIf cfg.enable {
    launchd.daemons.higgs = {
      serviceConfig = {
        Label = "org.higgs.server";
        ProgramArguments = [
          "/opt/homebrew/bin/higgs"
          "serve"
          "--config"
          "${darwinHomeDir}/.config/higgs/config.toml"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        WatchPaths = ["${darwinHomeDir}/.config/higgs/config.toml"];
        StandardOutPath = "/tmp/higgs.log";
        StandardErrorPath = "/tmp/higgs.err";
        EnvironmentVariables = {
          HOME = darwinHomeDir;
          USER = primaryUser;
        };
      };
    };
  };
}
