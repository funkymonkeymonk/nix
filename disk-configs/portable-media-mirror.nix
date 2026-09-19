# Portable external media storage
# Two 12 TB disks in a ZFS mirror for media and Nixarr state.
#
# The disks are identified by ATA serial symlinks rather than /dev/sdX names,
# which are not stable across USB reconnects.
{lib, ...}: {
  boot = {
    supportedFilesystems = ["zfs"];
    kernelModules = ["zfs"];
  };

  services.zfs.autoScrub.enable = true;

  disko.devices = {
    disk = {
      media0 = {
        device = lib.mkDefault "/dev/disk/by-id/ata-ST12000VN0008-2YS101_ZRT2MCJL";
        type = "disk";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "media";
            };
          };
        };
      };

      media1 = {
        device = lib.mkDefault "/dev/disk/by-id/ata-ST12000VN0008-2YS101_ZRT2MDDE";
        type = "disk";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "media";
            };
          };
        };
      };
    };

    zpool.media = {
      type = "zpool";
      mode = "mirror";
      rootFsOptions = {
        compression = "zstd";
        atime = "off";
      };
      options.ashift = "12";
      datasets = {
        library = {
          type = "zfs_fs";
          mountpoint = "/srv/media";
          mountOptions = [
            "nofail"
            "zfsutil"
            "x-systemd.automount"
          ];
          options = {
            recordsize = "1M";
          };
        };
      };
    };
  };
}
