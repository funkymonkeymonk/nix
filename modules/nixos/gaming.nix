# Gaming configuration for NixOS
# Steam, gamemode, controller support (Xbox One/xpadneo)
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.gaming;
in {
  options.myConfig.gaming = {
    enable = mkEnableOption "gaming support";
  };

  config = mkIf cfg.enable {
    programs = {
      steam = {
        enable = true;
        remotePlay.openFirewall = true;
        gamescopeSession.enable = true;
      };
      gamemode.enable = true;
    };

    # Xbox controller support
    hardware = {
      xone.enable = true;
      xpadneo.enable = true;
    };

    # Gaming packages
    environment.systemPackages = with pkgs; [
      lutris
      protonup-qt
    ];
  };
}
