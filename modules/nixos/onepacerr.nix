{
  config,
  lib,
  ...
}: {
  options.myConfig.onePacerr.enable = lib.mkEnableOption "OnePacerr";
  config = lib.mkIf config.myConfig.onePacerr.enable {
    virtualisation.oci-containers.containers.onepacerr = {
      image = "ghcr.io/eltharynd/onepacerr:latest";
      autoStart = true;
      environment = {
        LIBRARY_SERIES_NAME = "One Pace";
        TORRENT_CLIENT = "transmission";
        JELLYFIN_URL = "http://127.0.0.1:8096";
      };
    };
  };
}
