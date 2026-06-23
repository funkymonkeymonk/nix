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
  };
}
