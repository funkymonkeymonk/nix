{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.agent-skills;
in {
  config =
    lib.mkIf cfg.enable {
    };
}
