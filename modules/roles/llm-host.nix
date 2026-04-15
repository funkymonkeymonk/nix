{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.llm-host;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      ollama
    ];

    myConfig.ollama = {
      enable = true;
      host = "0.0.0.0";
      port = 11434;
      models = config.myConfig.sharedModels;
    };
  };
}
