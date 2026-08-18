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
      # AST-aware merge tool. jj ships a default `merge-tools.mergiraf`
      # entry out of the box (see `jj config list --include-defaults
      # merge-tools`), so no jj config is needed here -- just the binary
      # on PATH. Use `jj resolve --tool mergiraf [<path>]` to resolve
      # conflicts. See https://mergiraf.org/usage.html.
      mergiraf
    ];

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
