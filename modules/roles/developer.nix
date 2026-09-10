{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.developer;
  developerPackages = import ./developer-packages.nix {inherit pkgs;};
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = developerPackages;

    myConfig.zellij.enable = true;

    environment.shellAliases = {
      # Yaks shortcuts
      yl = "yx ls";
      yla = "yx ls --all";
      ya = "yx add";
      yd = "yx done";
      ys = "yx sync";
    };
  };
}
