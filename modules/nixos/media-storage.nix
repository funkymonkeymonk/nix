{...}: {
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.extraPools = ["media"];

  fileSystems."/srv/media" = {
    device = "/media";
    fsType = "none";
    options = [
      "bind"
      "nofail"
      "x-systemd.after=zfs-mount.service"
      "x-systemd.requires=zfs-mount.service"
    ];
  };
}
