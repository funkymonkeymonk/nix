# Zellij terminal multiplexer configuration
{
  osConfig,
  lib,
  ...
}:
with lib; let
  cfg = osConfig.myConfig.zellij;
in {
  config = mkIf cfg.enable {
    programs.zellij = {
      enable = true;
      settings = {
        theme = "dark";
        assumeUTF-8 = true;
      };
    };
  };
}
