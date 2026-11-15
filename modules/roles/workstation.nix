{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.workstation;
in {
  options.myConfig.roles.workstation.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Developer workstation/desktop tools (slack, trippy, unar)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      slack
      trippy
      unar
    ];
  };
}
