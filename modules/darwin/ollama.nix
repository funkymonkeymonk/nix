# Ollama service module for Darwin (macOS)
#
# Uses launchd to manage Ollama as a system daemon
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.ollama;

  # Script to start Ollama and pre-pull models
  ollamaStartScript = pkgs.writeShellScript "ollama-start" ''
    set -euo pipefail

    export OLLAMA_HOST="${cfg.host}:${toString cfg.port}"
    ${optionalString (cfg.acceleration == "cuda") "export OLLAMA_GPU_DRIVER=cuda"}
    ${optionalString (cfg.acceleration == "rocm") "export OLLAMA_GPU_DRIVER=rocm"}
    ${optionalString (cfg.acceleration == "metal") "export OLLAMA_GPU_DRIVER=metal"}

    # Start Ollama server in background
    ${pkgs.ollama}/bin/ollama serve &
    OLLAMA_PID=$!

    # Wait for Ollama to be ready
    echo "Waiting for Ollama to start..."
    for i in $(seq 1 30); do
      if ${pkgs.curl}/bin/curl -s "http://${cfg.host}:${toString cfg.port}/api/tags" > /dev/null 2>&1; then
        echo "Ollama is ready"
        break
      fi
      sleep 1
    done

    # Pre-pull configured models
    ${concatMapStringsSep "\n" (model: ''
        echo "Pulling model: ${model}"
        ${pkgs.ollama}/bin/ollama pull ${model} || echo "Failed to pull ${model}, continuing..."
      '')
      cfg.models}

    # Keep the server running
    wait $OLLAMA_PID
  '';
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.ollama];

    launchd.daemons.ollama = {
      serviceConfig = {
        Label = "org.ollama.server";
        ProgramArguments = ["${ollamaStartScript}"];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/ollama.log";
        StandardErrorPath = "/tmp/ollama.err";
        EnvironmentVariables = {
          HOME = "/Users/monkey";
          USER = "monkey";
          OLLAMA_HOST = "${cfg.host}:${toString cfg.port}";
          PATH = "/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin";
        };
      };
    };
  };
}
