{ config, lib, pkgs, ... }:

with lib;

let
  litellmConfig = pkgs.writeText "litellm-config.yaml" (builtins.readFile ../../../../configs/litellm/config.yaml);
in {
  config = mkIf (config.myConfig.litellm.enable or false) {
    home.packages = with pkgs; [
      (python3.withPackages (ps: with ps; [
        litellm
        fastapi
        uvicorn
        pyyaml
      ]))
    ];

    # litellm systemd service for user
    systemd.user.services.litellm = {
      Unit = {
        Description = "litellm server";
        After = [ "network.target" ];
      };
      
      Service = {
        ExecStart = "${pkgs.litellm}/bin/litellm --config ${litellmConfig} --port ${toString (config.myConfig.litellm.port or 4000)}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    # Environment variables for litellm
    home.sessionVariables = {
      LITELLM_MASTER_KEY = config.myConfig.litellm.masterKey or "sk-12345";
      OPENAI_API_KEY = config.myConfig.litellm.openaiApiKey or "";
      ANTHROPIC_API_KEY = config.myConfig.litellm.anthropicApiKey or "";
    };
  };
}