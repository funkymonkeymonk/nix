{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myConfig.onePacerr;
  envFile = "/run/secrets/onepacerr.env";
in {
  options.myConfig.onePacerr = {
    enable = lib.mkEnableOption "OnePacerr One Pace automation";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/eltharynd/onepacerr:latest";
    };
    jellyfinPasswordFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/secrets/jellyfin-admin-password";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;
    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers.onepacerr = {
      image = cfg.image;
      autoStart = true;
      environmentFiles = [envFile];
      environment = {
        LIBRARY_MEDIA_SERVER = "jellyfin";
        LIBRARY_SERIES_NAME = "One Pace";
        LIBRARY_SERIES_FOLDER_NAME = "One Pace";
        LIBRARY_CREATE_SHOW_IF_NOT_FOUND = "true";
        LIBRARY_USE_HARDLINKS = "false";
        JELLYFIN_URL = "http://127.0.0.1:8096";
        JELLYFIN_LIBRARY_NAME = "Shows";
        TORRENT_CLIENT = "transmission";
        TORRENT_URL = "http://127.0.0.1:9091/transmission/rpc";
        TORRENT_CATEGORY = "onepacerr";
        TORRENT_CATEGORY_ONCE_COMPLETED = "completed";
        TORRENT_CHECK_INTERVAL = "60";
        PIPELINE_SKIP_VERIFY_PRESENT_FILES = "true";
        PIPELINE_SKIP_ORGANIZE_PRESENT_FILES = "false";
        PIPELINE_SKIP_UPDATE_METADATA_PRESENT_FILES = "false";
        PIPELINE_PREFER_EXTENDED = "true";
        PIPELINE_PREFER_ALTERNATE = "true";
        MOUNT_LIBRARY_MEDIA_SERVER = "/srv/media/library/shows";
        MOUNT_LIBRARY_ONEPACERR = "/library/shows";
        MOUNT_DOWNLOADS_TORRENT = "/srv/media/torrents";
        MOUNT_DOWNLOADS_ONEPACERR = "/downloads";
      };
      extraOptions = ["--network=host"];
      volumes = [
        "/srv/media/library/shows:/library/shows"
        "/srv/media/torrents:/downloads"
      ];
    };

    systemd.services.onepacerr-env = {
      description = "Prepare OnePacerr secrets";
      wantedBy = ["multi-user.target"];
      after = ["opnix-secrets.service"];
      requires = ["opnix-secrets.service"];
      before = ["docker-onepacerr.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -m 600 /dev/null ${lib.escapeShellArg envFile}
        printf 'JELLYFIN_USERNAME=jellyfin\nJELLYFIN_PASSWORD=%s\n' "$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg cfg.jellyfinPasswordFile})" > ${lib.escapeShellArg envFile}
      '';
    };

    systemd.services.docker-onepacerr = {
      after = ["onepacerr-env.service" "transmission.service" "jellyfin.service"];
      requires = ["onepacerr-env.service" "transmission.service" "jellyfin.service"];
    };
  };
}
