# Notification Router - NixOS Service
# Systemd service for the notification router
# Import this on NixOS machines to auto-start the service
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.notify;
in {
  config = mkIf cfg.enable {
    systemd.services.notify-router = {
      description = "Notification Router HTTP API";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.notify-router}/bin/notify-router";
        Restart = "always";
        RestartSec = "5";
      };
    };
  };
}
