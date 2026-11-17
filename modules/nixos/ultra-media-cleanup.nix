{
  config,
  lib,
  pkgs,
  ...
}: let
  stageCfg = config.myConfig.ultraMediaDownloadStage;
  cfg = stageCfg.cleanup;
  remoteDisk = stageCfg.remoteDisk;
  remoteDiskMetricsDirectory = "/run/ultra-media-metrics";
  remoteDiskMetricsPath = "${remoteDiskMetricsDirectory}/ultra-seedbox.prom";
  remoteDiskArgs =
    (lib.optionalString remoteDisk.enable "--remote-disk-monitoring ")
    + "--remote-disk-capacity-bytes ${toString remoteDisk.capacityBytes} "
    + "--remote-disk-warning-threshold-bytes ${toString remoteDisk.warningThresholdBytes} "
    + "--remote-disk-metrics-path ${lib.escapeShellArg remoteDiskMetricsPath}";
  arrConfig = pkgs.writeText "ultra-media-cleanup-arr.json" (builtins.toJSON {
    libraryRoots = ["/srv/media/movies" "/srv/media/shows" "/srv/media/music"];
    arrApis = [
      {
        baseUrl = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}/api/v3";
        apiKeyFile = "/run/media-app-api-keys/radarr";
      }
      {
        baseUrl = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}/api/v3";
        apiKeyFile = "/run/media-app-api-keys/sonarr";
      }
      {
        baseUrl = "http://127.0.0.1:${toString config.services.lidarr.settings.server.port}/api/v1";
        apiKeyFile = "/run/media-app-api-keys/lidarr";
      }
    ];
  });
  modeArgs =
    if cfg.enable
    then "--apply"
    else "--report-only";
  trackerPolicyArgs = lib.optionalString cfg.privateTrackerRatioProtection.enable "--private-tracker-ratio-protection";
  cleanupQueueRoot = "/var/lib/ultra-media/cleanup-queue";
  enabledArrServices = [
    "radarr.service"
    "sonarr.service"
    "lidarr.service"
    "radarr-media-api-key.service"
    "sonarr-media-api-key.service"
    "lidarr-media-api-key.service"
  ];
  cleanupDependencies = lib.optionals cfg.enable (["opnix-secrets.service"] ++ enabledArrServices);
in {
  systemd.services.ultra-media-cleanup = {
    description = "Verify completed Ultra imports and clean eligible seedbox torrents";
    after = cleanupDependencies;
    wants = cleanupDependencies;
    requires = cleanupDependencies;
    unitConfig = {
      ConditionPathIsMountPoint = "/srv/media";
      RequiresMountsFor = ["/srv/media"];
    };
    environment.TMPDIR = "/run/ultra-media";
    serviceConfig =
      {
        Type = "oneshot";
        User = "ultra-sync";
        Group = "users";
        UMask = "0002";
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateNetwork = !cfg.enable;
        RuntimeDirectory = "ultra-media";
        RuntimeDirectoryMode = "0700";
        RuntimeDirectoryPreserve = "yes";
        StateDirectory = "ultra-media";
        StateDirectoryMode = "0700";
        ReadOnlyPaths = ["/srv/media"];
        ReadWritePaths = ["/run/ultra-media"] ++ lib.optionals remoteDisk.enable [remoteDiskMetricsDirectory];
        TimeoutStartSec = "15min";
      }
      // lib.optionalAttrs cfg.enable {
        SupplementaryGroups =
          [
            "media-management-secrets"
            "radarr-api"
            "sonarr-api"
            "lidarr-api"
          ]
          ++ lib.optionals remoteDisk.enable ["ultra-media-metrics"];
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      };
    script = ''
      set -euo pipefail
      export PYTHONPATH=${./scripts}
      exec ${pkgs.python3}/bin/python ${./scripts/ultra-media-cleanup.py} \
        ${modeArgs} \
        ${trackerPolicyArgs} \
        --queue-root ${lib.escapeShellArg cleanupQueueRoot} \
        --rpc-url /run/secrets/ultra-media-stage-rpc-url \
        --download-root /run/secrets/ultra-media-stage-download-root \
        --ssh-host /run/secrets/ultra-media-stage-host \
        --ssh-username /run/secrets/ultra-media-stage-username \
        --ssh-port 22 \
        --known-hosts /run/secrets/ultra-media-stage-known-hosts \
        --ssh-key /run/secrets/ultra-media-stage-key \
        --rpc-username /run/secrets/ultra-media-stage-rpc-username \
        --rpc-password /run/secrets/ultra-media-stage-rpc-password \
        --ssh ${pkgs.openssh}/bin/ssh \
        --ssh-keygen ${pkgs.openssh}/bin/ssh-keygen \
        --arr-config ${arrConfig} ${remoteDiskArgs}
    '';
  };

  systemd.timers.ultra-media-cleanup = {
    wantedBy = lib.optionals cfg.enable ["timers.target"];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      Unit = "ultra-media-cleanup.service";
    };
  };
}
