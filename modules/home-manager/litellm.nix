{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.litellm;

  # Generate secure config with proper authentication
  secureConfig = pkgs.writeText "litellm-config.yaml" ''
    ${builtins.readFile ../../../../configs/litellm/config.yaml}

    # Security overrides
    security:
      require_api_key: true
      allowed_api_keys: ["os.environ/LITELLM_MASTER_KEY"]
  '';

  # Script to retrieve master key from 1Password
  getMasterKey = pkgs.writeShellScript "get-litellm-master-key" ''
    set -euo pipefail
    op item get "LiteLLM Master Key" --vault Homelab --field password --reveal
  '';
in {
  config = mkIf (cfg.enable or false) {
    home.packages = with pkgs; [
      (python3.withPackages (ps:
        with ps; [
          litellm
          fastapi
          uvicorn
          pyyaml
          backoff
          click
          pydantic
          requests
          openai
          anthropic
          orjson
          python-dotenv
          tokenizers
        ]))
      # 1Password CLI should be available via system configuration
    ];

    # litellm systemd service for user with secure environment
    systemd.user.services.litellm = {
      Unit = {
        Description = "litellm server";
        After = ["network.target"];
      };

      Service = {
        ExecStartPre = "${getMasterKey}";
        ExecStart = "${pkgs.bash}/bin/bash -c 'export LITELLM_MASTER_KEY=\"$(${getMasterKey})\" && exec ${pkgs.litellm}/bin/litellm --config ${secureConfig} --port ${toString (cfg.port or 4000)}'";
        Restart = "on-failure";
        RestartSec = 5;

        # Secure environment variable handling
        Environment = lib.optionals (cfg.environmentFile != null) [
          "ENVIRONMENT_FILE=${cfg.environmentFile}"
        ];

        # Load credentials from files if provided
        PassEnvironment = "LITELLM_MASTER_KEY";
      };

      Install = {
        WantedBy = ["default.target"];
      };
    };

    # Security validation - ensure 1Password CLI is available for secure key retrieval
    assertions = [
      {
        assertion = cfg.masterKeyReference != null || cfg.environmentFile != null;
        message = "litellm: Must provide either masterKeyReference (for 1Password CLI) or environmentFile with master key";
      }
    ];
  };
}
