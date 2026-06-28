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
            # logseq removed: Build hangs for hours on electron-forge from source.
            # super-productivity disabled: Electron 41 kqueue assertion crash on macOS.
            # during electron-builder. Existing installed version (18.5.0) works fine.
            # Tracked: libuv kqueue.c:279 errno == EINTR
            # super-productivity
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
