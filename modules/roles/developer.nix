{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.developer;
in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      clang
      python3
      nodejs
      yarn
      k3d
      kubectl
      kubernetes-helm
      k9s
      gh-dash
      gomuks
      slidev-cli
      temporal-cli
      yaks
    ];

    myConfig.fjj.enable = true;
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
