{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.onepassword or {};
in {
  # Shell aliases configuration
  # This module contains aliases for programs NOT installed in base bundle

  home.shellAliases = {
    # Development tools
    try = "nix-shell -p";
    # Development tool aliases
    ops =
      if cfg.enable or false
      then "op signin"
      else ""; # 1Password CLI (conditional)
    # AI assistant aliases
    oc = "opencode";
    kk = "opencode run";
    # Git aliases
    newbranch = "git checkout -b $(date +\"%Y%m%d%H%M%S\")-";
  };
}
