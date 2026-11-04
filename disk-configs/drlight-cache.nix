{
  disko.devices.disk.cache = {
    device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S7L9NJ0Y422825N";
    type = "disk";
    content = {
      type = "gpt";
      partitions.cache = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/srv/local";
          mountOptions = ["noatime" "nodev" "nosuid" "nofail"];
        };
      };
    };
  };
}
