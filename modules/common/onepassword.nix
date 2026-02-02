{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.onepassword;
in {
  config = mkIf cfg.enable {
    # Install 1Password CLI via Nix packages
    programs._1password = {
      enable = true;
      package = pkgs._1password-cli;
    };
  };
}
