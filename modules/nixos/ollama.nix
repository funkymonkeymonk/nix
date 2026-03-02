# Ollama service module for NixOS (Linux)
#
# Uses systemd to manage Ollama as a system service
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

    systemd.services.ollama = {
      description = "Ollama Local LLM Server";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${ollamaStartScript}";
        Restart = "on-failure";
        RestartSec = "5s";
        Environment = [
          "OLLAMA_HOST=${cfg.host}:${toString cfg.port}"
          "PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin"
        ];
      };
    };

    # Open firewall if binding to non-localhost
    networking.firewall.allowedTCPPorts = mkIf (cfg.host != "127.0.0.1") [cfg.port];
  };
}
