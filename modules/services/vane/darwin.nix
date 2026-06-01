# Vane native launchd service for Darwin (macOS)
# Runs Vane directly (not in Docker), using the Nix package.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.vane;
  inherit (config._vaneCommon) searxngUrl;

  primaryUser =
    if config.myConfig.users != []
    then (builtins.head config.myConfig.users).name
    else "monkey";
  darwinHomeDir = "/Users/${primaryUser}";
  dataDir = cfg.dataDir;

  # Environment for Vane
  vaneEnv = {
    VANE_PORT = toString cfg.port;
    SEARXNG_API_URL = searxngUrl;
  } // optionalAttrs (cfg.openaiBaseUrl != null) {
    OPENAI_BASE_URL = cfg.openaiBaseUrl;
  } // optionalAttrs (cfg.ollamaUrl != null) {
    OLLAMA_API_URL = cfg.ollamaUrl;
  };

  vaneServiceScript = pkgs.writeShellScript "vane-launchd-service" ''
    set -euo pipefail
    export HOME="${darwinHomeDir}"
    export PATH="${pkgs.nodejs}/bin:/usr/local/bin:/usr/bin:/bin"

    mkdir -p "${dataDir}/vane" "${dataDir}/logs"

    cd "${dataDir}/vane"
    exec ${pkgs.vane}/bin/vane
  '';
in {
  imports = [./common.nix];

  config = mkIf cfg.enable {
    launchd.user.agents.vane = {
      serviceConfig = {
        Label = "com.vane.service";
        ProgramArguments = ["${vaneServiceScript}"];
        EnvironmentVariables = vaneEnv;
        RunAtLoad = cfg.autoStart;
        KeepAlive = true;
        StandardOutPath = "/tmp/vane.log";
        StandardErrorPath = "/tmp/vane.error.log";
        WorkingDirectory = "${dataDir}/vane";
      };
    };

    system.activationScripts.postActivation.text = mkAfter ''
      mkdir -p "${dataDir}/vane" "${dataDir}/logs"
    '';
  };
}
