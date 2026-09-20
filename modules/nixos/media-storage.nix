{...}: {
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.extraPools = ["media"];

  fileSystems."/srv/media" = {
    device = "media/library";
    fsType = "zfs";
    options = ["noatime"];
  };

  fileSystems."/media" = {
    device = "media/library";
    fsType = "zfs";
    options = ["noatime"];
  };
}
