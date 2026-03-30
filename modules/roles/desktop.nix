{
  config,
  options,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.desktop;
  inherit (config.myConfig) isDarwin;
  hasHomebrew = options ? homebrew;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge ([
        {
          environment.systemPackages = with pkgs; [
            logseq
            super-productivity
          ];
        }
        (lib.mkIf (!isDarwin) {
          environment.systemPackages = with pkgs; [
            element-desktop
            vivaldi
          ];
        })
      ]
      ++ lib.optionals hasHomebrew [
        (lib.mkIf isDarwin {
          homebrew.casks = [
            "element"
          ];
        })
      ])
  );
}
