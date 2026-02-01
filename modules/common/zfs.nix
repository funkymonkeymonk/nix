{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.myConfig.zfs;
  zfsCmd = "${pkgs.openzfs}/bin/zfs";
  zpoolCmd = "${pkgs.openzfs}/bin/zpool";
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
        kextload -b org.openzfs.zfs
      fi
    '';

    # Enable ZFS services
    launchd.daemons = {
      zfs = {
        script = ''
          # Start ZFS services with error handling
          if ! ${zpoolCmd} import -a 2>/dev/null; then
            echo "Warning: Some pools failed to import" >&2
          fi
          ${zfsCmd} mount -a
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
                ${zfsCmd} snapshot ${poolName}@$(date +%Y%m%d_%H%M%S)

                # Clean up old snapshots
                SNAPSHOTS=$(${zfsCmd} list -t snapshot -o name -H ${poolName}@ | tail -n +$((${pool.snapshotRetention} + 1)))
                if [[ -n "$SNAPSHOTS" ]]; then
                  echo "$SNAPSHOTS" | xargs -I {} ${zfsCmd} destroy {}
                fi
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
        ${zpoolCmd} status && ${zfsCmd} list
      '';
      zfs-health = ''
        ${zpoolCmd} status -x
      '';
    };
  };
}
