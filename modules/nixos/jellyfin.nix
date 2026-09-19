# Jellyfin media server for NixOS.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.jellyfin;
  mediaDirectories = ["movies" "tv" "music"];
in {
  options.myConfig.jellyfin = {
    enable = mkEnableOption "Jellyfin media server";

    mediaDir = mkOption {
      type = types.path;
      default = "/srv/media";
      description = "Root directory containing Jellyfin media libraries";
    };
  };

  config = mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = false;
    };

    myConfig.backup.paths = [
      {
        path = "/var/lib/jellyfin";
        exclude = ["cache" "transcodes"];
      }
    ];

    systemd.tmpfiles.rules = map (directory: "d ${cfg.mediaDir}/${directory} 0755 jellyfin jellyfin -") mediaDirectories;
  };
}
