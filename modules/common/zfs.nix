{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.zfs;
in {
  options.myConfig.zfs = {
    enable = mkEnableOption "ZFS filesystem support";

    pools = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          devices = mkOption {
            type = types.listOf types.str;
            description = "List of devices in the pool";
          };

          mountpoint = mkOption {
            type = types.str;
            description = "Default mountpoint for the pool";
            default = "/mnt";
          };

          encryption = mkOption {
            type = types.bool;
            description = "Enable pool encryption";
            default = false;
          };

          compression = mkOption {
            type = types.str;
            description = "Compression algorithm";
            default = "lz4";
          };

          snapshots = mkOption {
            type = types.bool;
            description = "Enable automatic snapshots";
            default = false;
          };

          snapshotRetention = mkOption {
            type = types.int;
            description = "Number of snapshots to retain";
            default = 30;
          };
        };
      });
      default = {};
    };
  };

  config = mkIf cfg.enable {
    # OpenZFS package for macOS
    environment.systemPackages = with pkgs; [
      openzfs
    ];

    # Load ZFS kernel extension (kext)
    system.activationScripts.postActivation.text = ''
      # Load ZFS kernel extension
      if ! kextstat | grep -q org.openzfs.zfs; then
        sudo kextload -b org.openzfs.zfs
      fi
    '';

    # Enable ZFS services
    launchd.daemons = {
      zfs = {
        script = ''
          # Start ZFS services
          /run/current-system/sw/bin/zpool import -a
          /run/current-system/sw/bin/zfs mount -a
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = true;
          StandardErrorPath = "/var/log/zfs.log";
          StandardOutPath = "/var/log/zfs.log";
        };
      };

      zfs-snapshot = mkIf (any (pool: pool.snapshots) (attrValues cfg.pools)) {
        script = ''
          # Create hourly snapshots
          ${lib.concatMapStringsSep "\n" (
            poolName: let
              pool = cfg.pools.${poolName};
            in
              lib.optionalString pool.snapshots ''
                /run/current-system/sw/bin/zfs snapshot ${poolName}@$(date +%Y%m%d_%H%M%S)

                # Clean up old snapshots
                /run/current-system/sw/bin/zfs list -t snapshot -o name ${poolName}@ | \
                  tail -n +$((${pool.snapshotRetention} + 2)) | \
                  xargs -I {} /run/current-system/sw/bin/zfs destroy {}
              ''
          ) (attrNames cfg.pools)}
        '';
        serviceConfig = {
          StartInterval = 3600; # Every hour
          StandardErrorPath = "/var/log/zfs-snapshot.log";
          StandardOutPath = "/var/log/zfs-snapshot.log";
        };
      };
    };

    # Create ZFS monitoring script
    environment.shellAliases = {
      zfs-status = ''
        ${pkgs.openzfs}/bin/zpool status && ${pkgs.openzfs}/bin/zfs list
      '';
      zfs-health = ''
        ${pkgs.openzfs}/bin/zpool status -x
      '';
    };
  };
}
