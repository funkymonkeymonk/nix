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
    ];

    # litellm systemd service for user with secure environment
    systemd.user.services.litellm = {
      Unit = {
        Description = "litellm server";
        After = ["network.target"];
      };

      Service =
        {
          ExecStart = "${pkgs.litellm}/bin/litellm --config ${secureConfig} --port ${toString (config.myConfig.litellm.port or 4000)}";
          Restart = "on-failure";
          RestartSec = 5;

          # Secure environment variable handling
          Environment =
            [
              "LITELLM_MASTER_KEY_FILE=${config.myConfig.litellm.masterKeyFile or ""}"
            ]
            ++ lib.optionals (config.myConfig.litellm.environmentFile != null) [
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

    # Security validation
    assertions = [
      {
        assertion = config.myConfig.litellm.masterKeyFile != null;
        message = "litellm.masterKeyFile must be set for security - hardcoded keys are not allowed";
      }
    ];
  };
}
