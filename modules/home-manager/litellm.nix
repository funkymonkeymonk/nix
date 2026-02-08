{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
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
  config = mkIf (config.myConfig.litellm.enable or false) {
    home.packages = with pkgs; [
      (python3.withPackages (ps:
        with ps; [
          litellm
          fastapi
          uvicorn
          pyyaml
        ]))
      unstable._1password-cli # Required for secure key retrieval
    ];

    # litellm systemd service for user with secure environment
    systemd.user.services.litellm = {
      Unit = {
        Description = "litellm server";
        After = ["network.target"];
      };

      Service =
        {
          ExecStartPre = "${getMasterKey}";
          ExecStart = "${pkgs.bash}/bin/bash -c 'export LITELLM_MASTER_KEY=\"$(${getMasterKey})\" && exec ${pkgs.litellm}/bin/litellm --config ${secureConfig} --port ${toString (config.myConfig.litellm.port or 4000)}'";
          Restart = "on-failure";
          RestartSec = 5;

          # Secure environment variable handling
          Environment = lib.optionals (config.myConfig.litellm.environmentFile != null) [
            "ENVIRONMENT_FILE=${config.myConfig.litellm.environmentFile}"
          ];

          # Load credentials from files if provided
          PassEnvironment = "LITELLM_MASTER_KEY";
        }
        // lib.optionalAttrs (config.myConfig.litellm.environmentFile != null) {
          EnvironmentFile = config.myConfig.litellm.environmentFile;
        };

      Install = {
        WantedBy = ["default.target"];
      };
    };

    # Security validation - ensure 1Password CLI is available for secure key retrieval
    assertions = [
      {
        assertion = config.programs._1password-cli.enable || config.myConfig.onepassword.enable;
        message = "1Password CLI must be enabled to securely retrieve LiteLLM master key";
      }
    ];
  };
}
