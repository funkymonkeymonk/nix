# Generic single-disk ext4 configuration
# Works for most desktops and servers with a single drive
# Device uses mkDefault so it can be overridden by nixos-anywhere
{lib, ...}: {
  disko.devices = {
    disk = {
      main = {
        # Use mkDefault so nixos-anywhere can override with actual disk
        # Common values: /dev/sda, /dev/nvme0n1, /dev/vda
        device = lib.mkDefault "/dev/sda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
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
  };
}
