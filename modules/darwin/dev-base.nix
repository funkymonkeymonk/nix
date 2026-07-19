# modules/darwin/dev-base.nix
# Darwin developer base module.
# Applies the shared dev-base configuration to a nix-darwin system.
#
# No home-manager, no opnix, no secrets, no machine-specific services.
# This is the minimal base that core-v2 and all other Darwin targets build on.
{
  lib,
  pkgs,
  ...
}: let
  devBase = import ../../library/dev-base.nix {inherit pkgs;};
in {
  environment.systemPackages = devBase.packages ++ [pkgs._1password-cli];
  environment.shellAliases = devBase.shellAliases;
  environment.variables = devBase.environmentVariables;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) ["claude-code"];

  nix.enable = false;
  documentation.enable = false;

  programs.zsh.enable = true;
}
