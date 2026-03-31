# Sunshine game streaming for NixOS
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.streaming;
in {
  options.myConfig.streaming = {
    enable = mkEnableOption "Sunshine game streaming";
  };

  config = mkIf cfg.enable {
    services.sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true; # needed for Wayland
      openFirewall = true;
    };
  };
}
