{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.workstation;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      slack
      trippy
      unar
    ];
  };
}
