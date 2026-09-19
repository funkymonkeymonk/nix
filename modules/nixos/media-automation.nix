# Native media-management services for NixOS.
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.myConfig.mediaAutomation;
  backupPaths = map (path: {inherit path;}) [
    "/var/lib/sonarr"
    "/var/lib/radarr"
    "/var/lib/prowlarr"
    "/var/lib/bazarr"
    "/var/lib/seerr"
  ];
in {
  options.myConfig.mediaAutomation.enable = mkEnableOption "media automation services";

  config = mkIf cfg.enable {
    users.groups.media = {};

    services = {
      sonarr = {
        enable = true;
        openFirewall = false;
        group = "media";
      };
      radarr = {
        enable = true;
        openFirewall = false;
        dataDir = "/var/lib/radarr";
        group = "media";
      };
      prowlarr = {
        enable = true;
        openFirewall = false;
      };
      bazarr = {
        enable = true;
        openFirewall = false;
        dataDir = "/var/lib/bazarr";
        group = "media";
      };
      seerr = {
        enable = true;
        openFirewall = false;
        configDir = "/var/lib/seerr";
        stateRevision = 1;
      };
    };

    # Native service hardening uses private user namespaces by default, which
    # prevents the *arr services from sharing the media group.
    systemd.services.sonarr.serviceConfig.PrivateUsers = mkForce false;
    systemd.services.radarr.serviceConfig.PrivateUsers = mkForce false;
    systemd.services.bazarr.serviceConfig.PrivateUsers = mkForce false;

    myConfig.backup.paths = backupPaths;
  };
}
