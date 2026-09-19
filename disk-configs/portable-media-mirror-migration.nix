# Temporary migration overlay for the portable media mirror.
#
# Include this module instead of portable-media-mirror.nix while copying existing
# data. The normal machine configuration must use the final mountpoints.
{...}: {
  imports = [./portable-media-mirror.nix];

  disko.devices.zpool.media.datasets = {
    library.mountpoint = "/mnt/media";
  };
}
