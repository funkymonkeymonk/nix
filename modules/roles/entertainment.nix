{
  config,
  options,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.entertainment;
  inherit (config.myConfig) isDarwin;
  hasHomebrew = options ? homebrew;
  # programs.steam is a NixOS-only module; check for NixOS-specific options
  # at module-definition time (not config time) to avoid infinite recursion.
  isNixOS = builtins.hasAttr "boot" options;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge (
      [
        # NixOS-specific configuration — optionalAttrs so Darwin (which lacks
        # programs.steam) never evaluates these paths.
        (lib.optionalAttrs isNixOS {
          programs.steam.enable = true;
          environment.systemPackages = with pkgs; [
            obs-studio
            discord
          ];
        })
      ]
      ++ lib.optionals hasHomebrew [
        (lib.mkIf isDarwin {
          homebrew.casks = [
            "steam"
            "obs"
            "discord"
          ];
        })
      ]
    )
  );
}
