{
  config,
  options,
  lib,
  ...
}: let
  cfg = config.myConfig.roles.entertainment;
  inherit (config.myConfig) isDarwin;
  hasHomebrew = options ? homebrew;
in {
  config = lib.mkIf cfg.enable (
    lib.mkMerge (
      lib.optionals hasHomebrew [
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
