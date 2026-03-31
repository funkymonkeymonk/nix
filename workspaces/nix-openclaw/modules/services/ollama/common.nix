# Shared Ollama configuration and scripts
#
# This module provides common functionality used by the main ollama module.
# It exposes shared values via config._ollamaCommon for internal use.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.ollama;

  # Environment variables shared across platforms
  baseEnvironment = {
    OLLAMA_HOST = "${cfg.host}:${toString cfg.port}";
  };

  # GPU acceleration environment variables
  accelerationEnv =
    optionalAttrs (cfg.acceleration == "cuda") {OLLAMA_GPU_DRIVER = "cuda";}
    // optionalAttrs (cfg.acceleration == "rocm") {OLLAMA_GPU_DRIVER = "rocm";}
    // optionalAttrs (cfg.acceleration == "metal") {OLLAMA_GPU_DRIVER = "metal";};

  # Combined environment
  serviceEnvironment = baseEnvironment // accelerationEnv;

  # Script to wait for Ollama to be ready and pull models
  modelPullScript = pkgs.writeShellScript "ollama-pull-models" ''
    set -euo pipefail

    OLLAMA_HOST="${cfg.host}:${toString cfg.port}"
    MAX_RETRIES=30
    RETRY_INTERVAL=1

    echo "Waiting for Ollama to be ready..."
    for i in $(seq 1 $MAX_RETRIES); do
      if ${pkgs.curl}/bin/curl -s "http://${cfg.host}:${toString cfg.port}/api/tags" > /dev/null 2>&1; then
        echo "Ollama is ready"
        break
      fi
      if [ "$i" -eq "$MAX_RETRIES" ]; then
        echo "ERROR: Ollama failed to start within $MAX_RETRIES seconds"
        exit 1
      fi
      sleep $RETRY_INTERVAL
    done

    # Pre-pull configured models
    ${concatMapStringsSep "\n" (model: ''
        echo "Pulling model: ${model}"
        ${pkgs.ollama}/bin/ollama pull ${model} || echo "WARNING: Failed to pull ${model}, continuing..."
      '')
      cfg.models}

    echo "Model pull complete"
  '';

  # Main start script that launches Ollama and pulls models
  ollamaStartScript = pkgs.writeShellScript "ollama-start" ''
    set -euo pipefail

    # Set up environment
    export OLLAMA_HOST="${cfg.host}:${toString cfg.port}"
    ${optionalString (cfg.acceleration == "cuda") "export OLLAMA_GPU_DRIVER=cuda"}
    ${optionalString (cfg.acceleration == "rocm") "export OLLAMA_GPU_DRIVER=rocm"}
    ${optionalString (cfg.acceleration == "metal") "export OLLAMA_GPU_DRIVER=metal"}

    # Load environment file if specified
    ${optionalString (cfg.environmentFile != null) ''
      if [ -f "${cfg.environmentFile}" ]; then
        echo "Loading environment from ${cfg.environmentFile}"
        set -a
        source "${cfg.environmentFile}"
        set +a
      else
        echo "WARNING: Environment file ${cfg.environmentFile} not found"
      fi
    ''}

    # Start Ollama server in background
    ${pkgs.ollama}/bin/ollama serve &
    OLLAMA_PID=$!

    # Pull models after server starts
    ${modelPullScript} &

    # Keep the server running
    wait $OLLAMA_PID
  '';
in {
  # Internal option for sharing values between modules (not user-facing)
  options._ollamaCommon = mkOption {
    type = types.attrs;
    internal = true;
    description = "Internal: Shared Ollama configuration values";
  };

  # Export shared values for use by the main module
  config._ollamaCommon = {
    inherit serviceEnvironment ollamaStartScript modelPullScript;
    packages = [pkgs.ollama];
    pathEnv = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin";
  };
}
