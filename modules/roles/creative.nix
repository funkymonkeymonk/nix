{
  config,
  options,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.roles.creative;
  inherit (config.myConfig) isDarwin;
  hasHomebrew = options ? homebrew;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge ([
        {
          environment.systemPackages = with pkgs; [
            ffmpeg
            imagemagick
            pandoc
          ];
        }
      ]
      ++ lib.optionals hasHomebrew [
        (lib.mkIf isDarwin {
          homebrew.casks = [
            "elgato-stream-deck"
          ];
        })
      ])
  );
}
