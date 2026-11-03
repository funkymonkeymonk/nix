{pkgs, ...}: {
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.extraPools = ["media"];

  # Keep the parent pool dataset from mounting over the media/library dataset.
  # The latter is mounted explicitly by NixOS at the service-facing path below.
  systemd.services.zfs-media-mountpoints = {
    description = "Set Drlight media ZFS mountpoints";
    after = ["zfs-import-media.service"];
    before = ["zfs-mount.service" "srv-media.mount"];
    wantedBy = ["zfs-mount.service"];
    requiredBy = ["srv-media.mount"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.zfs}/sbin/zfs set mountpoint=none media
      ${pkgs.zfs}/sbin/zfs set mountpoint=legacy media/library
    '';
  };

  fileSystems."/srv/media" = {
    device = "media/library";
    fsType = "zfs";
    options = ["nofail" "zfsutil"];
  };

  systemd.tmpfiles.rules = [
    "d /srv/local/cache/ultra 0750 root root - -"
    "d /srv/local/state 0750 root root - -"
  ];
}
