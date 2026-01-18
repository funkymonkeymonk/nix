{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.agent-skills;
in {
  config = lib.mkIf cfg.enable {
    # Create skills directories
    home.file."${cfg.skillsPath}/.keep" = {
      text = "";
    };

    home.file."${cfg.superpowersPath}/.keep" = {
      text = "";
    };
  };
}
