{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.gaming;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      moonlight-qt
    ];
  };
}
