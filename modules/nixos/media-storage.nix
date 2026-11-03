{pkgs, ...}: {
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.extraPools = ["media"];

  # Keep the parent pool dataset from mounting over the media/library dataset.
  # ZFS mounts media/library directly at the service-facing path below.
  systemd.services.zfs-media-mountpoints = {
    description = "Set Drlight media ZFS mountpoints";
    after = ["zfs-import-media.service"];
    before = ["zfs-mount.service" "jellyfin.service"];
    wantedBy = ["zfs-mount.service"];
    requiredBy = ["jellyfin.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.zfs}/sbin/zfs set mountpoint=none media
      ${pkgs.zfs}/sbin/zfs set mountpoint=/srv/media media/library
    '';
  };

  systemd.services.jellyfin = {
    after = ["zfs-mount.service"];
    unitConfig.ConditionPathIsMountPoint = "/srv/media";
  };

  systemd.tmpfiles.rules = [
    "d /srv/local/cache/ultra 0750 root root - -"
    "d /srv/local/state 0750 root root - -"
  ];
}
