# Drlight's OS disk layout. The media ZFS mirror is intentionally excluded.
{...}: {
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/ata-Patriot_P210_512GB_P210IICB25030501733";
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
            preCreateHook = ''mkfs.vfat -F 32 "$device"'';
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
        swap = {
          size = "8G";
          content = {
            type = "swap";
            discardPolicy = "both";
          };
        };
      };
    };
  };
}
