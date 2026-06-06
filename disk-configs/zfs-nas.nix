# ZFS NAS disk configuration
# Boot disk (ext4) + ZFS data pool for document/media storage
#
# Deployment notes:
#   Disk assignments use lib.mkDefault so nixos-anywhere (or a host-specific
#   overlay) can override the actual device paths at install time.
#
#   For mirror or RAIDZ layouts, add additional disks below that reference
#   pool = "tank" and set `disko.devices.zpool.tank.mode` accordingly
#   (e.g. "mirror", "raidz1", "raidz2").
{lib, ...}: {
  disko.devices = {
    disk = {
      # Boot disk - small SSD for OS
      boot = {
        device = lib.mkDefault "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = ["umask=0077"];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };

      # First data disk - member of the "tank" zpool.
      # For mirrors or RAIDZ, copy this block as `tank1`, `tank2`, etc.,
      # pointing each at a distinct device.
      tank0 = {
        device = lib.mkDefault "/dev/sdb";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "tank";
              };
            };
          };
        };
      };
    };

    zpool = {
      # Main data pool. Disks are assigned via the partitions above
      # (content.type = "zfs"; content.pool = "tank";).
      # Change `mode` to "mirror", "raidz1", "raidz2" when adding more disks.
      tank = {
        type = "zpool";

        rootFsOptions = {
          compression = "zstd";
          "com.sun:auto-snapshot" = "false";
        };

        options.ashift = "12";

        datasets = {
          # Container for all data
          data = {
            type = "zfs_fs";
            mountpoint = "/tank/data";
            options = {
              compression = "zstd";
              atime = "off";
            };
          };

          # Paperless document storage
          paperless = {
            type = "zfs_fs";
            mountpoint = "/var/lib/paperless";
            options = {
              compression = "zstd";
              recordsize = "1M"; # Good for documents
              atime = "off";
            };
          };

          # Backups and snapshots
          backup = {
            type = "zfs_fs";
            mountpoint = "/tank/backup";
            options = {
              compression = "zstd";
              atime = "off";
            };
          };

          # General media storage
          media = {
            type = "zfs_fs";
            mountpoint = "/tank/media";
            options = {
              compression = "zstd";
              recordsize = "1M";
              atime = "off";
            };
          };
        };
      };
    };
  };
}
