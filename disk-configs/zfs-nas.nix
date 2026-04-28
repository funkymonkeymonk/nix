# ZFS NAS disk configuration
# Boot disk (ext4) + ZFS data pool for document/media storage
# Supports mirroring and RAIDZ configurations
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
    };

    zpool = {
      # Main data pool - configured at deploy time via device override
      # Examples:
      #   Single disk:   device = "/dev/sdb";
      #   Mirror:        devices = ["/dev/sdb" "/dev/sdc"];
      #   RAIDZ1 (3+):   devices = ["/dev/sdb" "/dev/sdc" "/dev/sdd"];
      tank = {
        type = "zpool";
        # Must be set during deployment - see examples above
        device = lib.mkDefault "/dev/sdb";

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
