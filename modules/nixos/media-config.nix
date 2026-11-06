{
  config,
  lib,
  ...
}: let
  cfg = config.myConfig.mediaConfig;
  mediaLibraryPaths = map (name: "/srv/media/${name}") [
    "audiobooks"
    "books"
    "comics"
    "movies"
    "music"
    "shows"
  ];
in {
  options.myConfig.mediaConfig.enable = lib.mkEnableOption "media services";

  config = lib.mkIf cfg.enable {
    services.jellyfin.enable = true;
    services.jellyfin.openFirewall = false;

    systemd.services.jellyfin = {
      after = ["zfs-mount.service" "media-library-folders.service"];
      requires = ["media-library-folders.service"];
      unitConfig = {
        ConditionPathIsMountPoint = "/srv/media";
        RequiresMountsFor = ["/srv/media"];
      };
    };

    systemd.services.media-library-folders = {
      description = "Create media library roots on the ZFS dataset";
      wantedBy = ["multi-user.target"];
      requires = ["zfs-mount.service"];
      after = ["zfs-mount.service"];
      before = ["jellyfin.service"];
      unitConfig.ConditionPathIsMountPoint = "/srv/media";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -eu
        ${lib.concatMapStringsSep "\n" (path: ''
            install -d -o root -g users -m 2775 ${lib.escapeShellArg path}
          '')
          mediaLibraryPaths}
      '';
    };
  };
}
