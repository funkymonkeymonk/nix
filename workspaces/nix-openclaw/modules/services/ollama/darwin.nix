# Ollama service module for Darwin (macOS)
#
# Uses launchd to manage Ollama as a system daemon.
# Imports shared configuration from common.nix.
# Uses nixpkgs ollama package (v0.17.7) which is kept up-to-date by the Nix community.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.ollama;

  # Common values are exposed via config._ollamaCommon from common.nix
  inherit (config._ollamaCommon) serviceEnvironment ollamaStartScript pathEnv packages;

  # Get the first configured user for Darwin launchd environment
  # Falls back to a generic "ollama" user if no users configured
  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "ollama";

  # Darwin home directory based on user
  darwinHomeDir = "/Users/${primaryUser}";
in {
  imports = [./common.nix];

  config = mkIf cfg.enable {
    environment.systemPackages = packages;

    launchd.daemons.ollama = {
      serviceConfig = {
        Label = "org.ollama.server";
        ProgramArguments = ["${ollamaStartScript}"];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/ollama.log";
        StandardErrorPath = "/tmp/ollama.err";
        EnvironmentVariables =
          serviceEnvironment
          // {
            HOME = darwinHomeDir;
            USER = primaryUser;
            PATH = pathEnv;
          };
      };
    };
  };
}
