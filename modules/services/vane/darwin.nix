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
  resolvedBaseUrl =
    if cfg.openaiBaseUrl != null
    then cfg.openaiBaseUrl
    else "http://localhost:8000/v1";

  # Environment for Vane
  # OPENAI_BASE_URL is omitted — it triggers Vane to auto-create a duplicate provider.
  # The base URL is set in the pre-created config.json instead.
  vaneEnv =
    {
      VANE_PORT = toString cfg.port;
      SEARXNG_API_URL = searxngUrl;
    }
    // optionalAttrs (cfg.ollamaUrl != null) {
      OLLAMA_API_URL = cfg.ollamaUrl;
    };

  vaneServiceScript = pkgs.writeShellScript "vane-launchd-service" ''
        set -euo pipefail
        export HOME="${darwinHomeDir}"
        export PATH="${pkgs.nodejs}/bin:/usr/local/bin:/usr/bin:/bin"
        export DATA_DIR="${dataDir}"

        mkdir -p "${dataDir}/data" "${dataDir}/logs"

        # Symlink drizzle directory so Vane can find migration files
        if [ ! -L "${dataDir}/drizzle" ]; then
          ln -sf "${pkgs.vane}/lib/vane/drizzle" "${dataDir}/drizzle"
        fi

        # Write Nix-managed config (always overwrites to stay in sync)
        cat > "${dataDir}/data/config.json" << VANECONFIG
    {
      "version": 1,
      "setupComplete": true,
      "modelProviders": [
        {
          "id": "higgs-local",
          "name": "Higgs Gateway (local)",
          "type": "openai",
          "chatModels": [
            {"name": "qwen-coder", "key": "qwen-coder"},
            {"name": "qwen-35b", "key": "qwen-35b"}
          ],
          "embeddingModels": [
            {"name": "qwen-embed", "key": "qwen-embed"}
          ],
          "config": {
            "apiKey": "higgs-local",
            "baseURL": "${resolvedBaseUrl}"
          }
        }
      ],
      "search": {
        "searxngURL": "${searxngUrl}"
      }
    }
    VANECONFIG

        exec ${pkgs.vane}/bin/vane
  '';
in {
  imports = [./common.nix];

  config = mkIf cfg.enable {
    launchd.daemons.vane = {
      serviceConfig = {
        Label = "com.vane.service";
        ProgramArguments = ["${vaneServiceScript}"];
        EnvironmentVariables = vaneEnv;
        RunAtLoad = cfg.autoStart;
        KeepAlive = true;
        UserName = primaryUser;
        StandardOutPath = "/tmp/vane.log";
        StandardErrorPath = "/tmp/vane.error.log";
        WorkingDirectory = "${darwinHomeDir}/.local/share/vane";
      };
    };

    system.activationScripts.postActivation.text = mkAfter ''
      mkdir -p "${dataDir}/data" "${dataDir}/logs"
    '';
  };
}
