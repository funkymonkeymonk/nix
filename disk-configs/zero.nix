# Zero NVMe desktop disk layout
# 1G ESP, ~913G ext4 root, 17G swap
# Uses explicit PARTUUIDs matching existing install — no disk changes needed
{lib, ...}: {
  disko.devices = {
    disk = {
      main = {
        device = lib.mkDefault "/dev/nvme0n1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              uuid = "4911b6cd-078d-4186-b3a4-8b046430ca72";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            root = {
              size = "100%";
              uuid = "684af983-9997-4abb-abb9-28a36e5c2dd5";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            swap = {
              size = "17G";
              uuid = "c7944ae6-b165-4266-933f-e0c7c53bf4c0";
              content = {
                type = "swap";
                discardPolicy = "both";
              };
            };
          };
        };
      };
    };
  };
}
