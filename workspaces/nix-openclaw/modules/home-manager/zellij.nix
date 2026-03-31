# Zellij terminal multiplexer configuration
{
  osConfig,
  lib,
  pkgs,
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

    home.file.".config/zellij/plugins/zellij-pane-tracker.wasm".source = "${pkgs.zellij-pane-tracker}/share/zellij/plugins/zellij-pane-tracker.wasm";
  };
}
