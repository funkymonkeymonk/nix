{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.gaming;
in {
  options.myConfig.roles.gaming.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Gaming tools (moonlight-qt)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      moonlight-qt
    ];
  };
}
