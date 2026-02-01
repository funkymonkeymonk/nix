{
  config,
  lib,
  pkgs,
  ...
}: {
  # ZFS configuration for external drives
  myConfig.zfs = {
    enable = true;

    pools = {
      # Main data pool for external drives
      "data_pool" = {
        devices = [
          # These will be updated with actual device paths
          "disk1"
          "disk2"
        ];
        mountpoint = "/Volumes/data_pool";
        encryption = true;
        compression = "lz4";
        snapshots = true;
        snapshotRetention = 30;
      };
    };
  };

  # Additional macOS-specific ZFS settings
  environment.systemPackages = with pkgs; [
    # Add ZFS monitoring tools
    htop
    iotop
  ];
}
