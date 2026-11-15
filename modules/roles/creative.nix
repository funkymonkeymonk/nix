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
  options.myConfig.roles.creative.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Media tools (ffmpeg, imagemagick, pandoc)";
  };

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
          homebrew.casks = lib.mkAfter ["elgato-stream-deck"];
        })
      ])
  );
}
