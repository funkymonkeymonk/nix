# Notification Router - Darwin Service
# Launchd service for the notification router on macOS
# Import this on Darwin machines to auto-start the service
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
    launchd.agents.notify-router = {
      enable = true;
      config = {
        Label = "org.nixos.notify-router";
        ProgramArguments = ["${pkgs.notify-router}/bin/notify-router"];
        RunAtLoad = true;
        KeepAlive = true;
        StandardOutPath = "/tmp/notify-router.log";
        StandardErrorPath = "/tmp/notify-router.error.log";
        EnvironmentVariables = {
          PATH = "/usr/bin:/bin:/usr/sbin:/sbin:${pkgs.curl}/bin:${pkgs.jq}/bin:${pkgs.netcat}/bin";
        };
      };
    };
  };
}
