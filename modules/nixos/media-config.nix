{
  config,
  lib,
  ...
}: {
  options.myConfig.mediaConfig.enable = lib.mkEnableOption "media services";
  config = lib.mkIf config.myConfig.mediaConfig.enable {
    services.jellyfin.enable = true;
    services.jellyfin.openFirewall = false;
    systemd.services.jellyfin.serviceConfig.RequiresMountsFor = ["/srv/media"];
  };
}
