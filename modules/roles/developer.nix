{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.developer;
  developerPackages = import ./developer-packages.nix {inherit pkgs;};
in {
  options.myConfig.roles.developer.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Development tools (clang, python, node, k8s, gh-dash)";
  };

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
