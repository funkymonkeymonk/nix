{
  config,
  lib,
  pkgs,
  ...
}: let
  keyPath = "/run/secrets/ultra-media-stage-key";
  hostPath = "/run/secrets/ultra-media-stage-host";
  usernamePath = "/run/secrets/ultra-media-stage-username";
  knownHostsPath = "/run/secrets/ultra-media-stage-known-hosts";
  rpcUrlPath = "/run/secrets/ultra-media-stage-rpc-url";
  downloadRootPath = "/run/secrets/ultra-media-stage-download-root";
  rpcUsernamePath = "/run/secrets/ultra-media-stage-rpc-username";
  rpcPasswordPath = "/run/secrets/ultra-media-stage-rpc-password";
  stagingRoot = "/srv/media/.arr-staging";
  cleanupQueueRoot = "/var/lib/ultra-media/cleanup-queue";
  sshPort = 22;
  stageCfg = config.myConfig.ultraMediaDownloadStage;
  stageServices = ["ultra-media-download-stage"];
  cleanupEnabled = stageCfg.cleanup.enable or false;
  remoteDiskConfig = stageCfg.remoteDisk;
  remoteDiskEnabled = remoteDiskConfig.enable;
  cleanupConfig = stageCfg.cleanup;
  remoteDiskMetricsDirectory = "/run/ultra-media-metrics";
  remoteDiskMetricsPath = "${remoteDiskMetricsDirectory}/ultra-seedbox.prom";
  syncMetricsPath = "${remoteDiskMetricsDirectory}/ultra-media-sync.prom";
  mediaApiKeyPath = name: "/run/media-app-api-keys/${name}";
  radarrUrl = "http://127.0.0.1:${toString config.services.radarr.settings.server.port}/api/v3";
  sonarrUrl = "http://127.0.0.1:${toString config.services.sonarr.settings.server.port}/api/v3";
  lidarrUrl = "http://127.0.0.1:${toString config.services.lidarr.settings.server.port}/api/v1";
  jellyfinUrl = "http://127.0.0.1:8096";
  remoteDiskArgs =
    (lib.optionalString remoteDiskEnabled "--remote-disk-monitoring ")
    + "--remote-disk-capacity-bytes ${toString remoteDiskConfig.capacityBytes} "
    + "--remote-disk-warning-threshold-bytes ${toString remoteDiskConfig.warningThresholdBytes} "
    + "--remote-disk-metrics-path ${lib.escapeShellArg remoteDiskMetricsPath}";
  cleanupPolicyArgs =
    "--min-completion-age-hours ${toString cleanupConfig.minCompletionAgeHours} "
    + "--min-torrent-ratio ${toString cleanupConfig.minTorrentRatio}";
  arrSyncServices = [
    "radarr-media-config-sync"
    "sonarr-media-config-sync"
    "lidarr-media-config-sync"
  ];
  mediaStatusServices = map (service: "${service}.service") (arrSyncServices ++ ["radarr-media-api-key" "sonarr-media-api-key" "lidarr-media-api-key"]);
  mkSecret = reference: path: {
    inherit reference path;
    mode = "0400";
    owner = "ultra-sync";
    group = "users";
    services = stageServices;
  };
  mkSharedSecret = reference: path: {
    inherit reference path;
    mode = "0440";
    owner = "root";
    group = "media-management-secrets";
    services = stageServices ++ arrSyncServices;
  };
in {
  imports = [
    ({lib, ...}: {
      options.myConfig.ultraMediaDownloadStage = {
        enable = lib.mkEnableOption "completed Ultra download staging timer";
        cleanup = {
          enable = lib.mkEnableOption "remove retention-eligible seedbox torrents after verified staging";
          privateTrackerRatioProtection.enable = lib.mkEnableOption "future private-tracker account-ratio cleanup gate (unknown trackers fail closed)";
          minCompletionAgeHours = lib.mkOption {
            type = lib.types.ints.positive;
            default = 240;
            description = "Minimum completion age in hours before a verified torrent may be removed.";
          };
          minTorrentRatio = lib.mkOption {
            type = lib.types.float;
            default = 3.0;
            description = "Minimum upload/download ratio before a verified torrent may be removed.";
          };
        };
        remoteDisk = {
          enable = lib.mkEnableOption "Ultra seedbox account storage monitoring";
          capacityBytes = lib.mkOption {
            type = lib.types.ints.positive;
            default = 4000000000000;
            description = "Nominal remote seedbox account capacity in decimal bytes.";
          };
          warningThresholdBytes = lib.mkOption {
            type = lib.types.ints.positive;
            default = 3000000000000;
            description = "Remote seedbox storage warning threshold in bytes.";
          };
        };
      };
    })
  ];

  users.groups =
    {
      media-management-secrets = {};
    }
    // lib.optionalAttrs remoteDiskEnabled {
      ultra-media-metrics = {};
    };
  users.users.ultra-sync = {
    isSystemUser = true;
    group = "users";
    extraGroups = ["media-management-secrets"] ++ lib.optionals remoteDiskEnabled ["ultra-media-metrics"];
    description = "Stage completed Ultra downloads for local Arr imports";
  };

  assertions = [
    {
      assertion = !remoteDiskEnabled || cleanupEnabled;
      message = "Ultra remote disk monitoring requires automatic cleanup to be enabled";
    }
    {
      assertion = !remoteDiskEnabled || remoteDiskConfig.warningThresholdBytes <= remoteDiskConfig.capacityBytes;
      message = "Ultra remote disk warning threshold must not exceed the configured capacity";
    }
  ];
  users.users.node-exporter.extraGroups = lib.optionals remoteDiskEnabled ["ultra-media-metrics"];
  myConfig.nodeExporter.textfileDirectory =
    if remoteDiskEnabled
    then remoteDiskMetricsDirectory
    else null;
  systemd.tmpfiles.rules = lib.optionals remoteDiskEnabled [
    "d ${remoteDiskMetricsDirectory} 2750 ultra-sync ultra-media-metrics - -"
    "z ${remoteDiskMetricsDirectory} 2750 ultra-sync ultra-media-metrics - -"
  ];

  myConfig.onepassword.secrets = {
    ultraMediaStageHost = mkSecret "Ultra Media Sync Config/host" hostPath;
    ultraMediaStageUsername = mkSecret "Ultra Media Sync Config/username" usernamePath;
    ultraMediaStageKnownHosts = mkSecret "Ultra Media Sync Config/knownHosts" knownHostsPath;
    ultraMediaStageKey = mkSecret "Ultra Media Sync Key/private key" keyPath;
    ultraMediaStageRpcUrl = mkSharedSecret "Ultra Media Sync Config/rpcUrl" rpcUrlPath;
    ultraMediaStageDownloadRoot = mkSharedSecret "Ultra Media Sync Config/completedDownloadsRoot" downloadRootPath;
    ultraMediaStageRpcUsername = mkSharedSecret "Ultra - Transmission/username" rpcUsernamePath;
    ultraMediaStageRpcPassword = mkSharedSecret "Ultra - Transmission/password" rpcPasswordPath;
  };

  systemd.services.ultra-media-download-stage = {
    description = "Sync completed downloads to Drlight and clean retention-eligible seedbox torrents";
    after = ["network-online.target" "zfs-mount.service" "media-management-roots.service" "opnix-secrets.service" "jellyfin.service"] ++ mediaStatusServices;
    wants = ["network-online.target" "jellyfin.service"] ++ mediaStatusServices;
    requires = ["zfs-mount.service" "media-management-roots.service" "opnix-secrets.service"];
    unitConfig = {
      ConditionPathIsMountPoint = "/srv/media";
      RequiresMountsFor = ["/srv/media"];
    };
    serviceConfig = {
      Type = "exec";
      User = "ultra-sync";
      Group = "users";
      SupplementaryGroups = ["media-management-secrets" "radarr-api" "sonarr-api" "lidarr-api" "media-auth-jellyfin"] ++ lib.optionals remoteDiskEnabled ["ultra-media-metrics"];
      UMask = "0002";
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      RuntimeDirectory = "ultra-media";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "yes";
      StateDirectory = "ultra-media";
      StateDirectoryMode = "0700";
      ReadWritePaths = [stagingRoot "/run/ultra-media"] ++ lib.optionals remoteDiskEnabled [remoteDiskMetricsDirectory];
    };
    environment.TMPDIR = "/run/ultra-media";
    script = ''
      set -euo pipefail
      export PYTHONPATH=${./scripts}
      exec ${pkgs.python3}/bin/python ${./scripts/ultra-media-sync.py} \
        --rpc-url ${lib.escapeShellArg rpcUrlPath} \
        --download-root ${lib.escapeShellArg downloadRootPath} \
        --ssh-host ${lib.escapeShellArg hostPath} \
        --ssh-username ${lib.escapeShellArg usernamePath} \
        --ssh-port ${toString sshPort} \
        --known-hosts ${lib.escapeShellArg knownHostsPath} \
        --ssh-key ${lib.escapeShellArg keyPath} \
        --rpc-username ${lib.escapeShellArg rpcUsernamePath} \
        --rpc-password ${lib.escapeShellArg rpcPasswordPath} \
        --ssh ${pkgs.openssh}/bin/ssh \
        --ssh-keygen ${pkgs.openssh}/bin/ssh-keygen \
        --rsync ${pkgs.rsync}/bin/rsync \
         --queue-root ${lib.escapeShellArg cleanupQueueRoot} \
         --metrics-path ${lib.escapeShellArg syncMetricsPath} \
         --radarr-url ${lib.escapeShellArg radarrUrl} \
         --sonarr-url ${lib.escapeShellArg sonarrUrl} \
         --lidarr-url ${lib.escapeShellArg lidarrUrl} \
         --jellyfin-url ${lib.escapeShellArg jellyfinUrl} \
         --radarr-api-key-file ${lib.escapeShellArg (mediaApiKeyPath "radarr")} \
         --sonarr-api-key-file ${lib.escapeShellArg (mediaApiKeyPath "sonarr")} \
         --lidarr-api-key-file ${lib.escapeShellArg (mediaApiKeyPath "lidarr")} \
         --jellyfin-username-file /run/secrets/jellyfin-admin-username \
         --jellyfin-password-file /run/secrets/jellyfin-admin-password \
         ${lib.optionalString cleanupEnabled "--cleanup-enabled "}\
         ${lib.optionalString stageCfg.cleanup.privateTrackerRatioProtection.enable "--private-tracker-ratio-protection "}\
         ${cleanupPolicyArgs} \
         ${remoteDiskArgs}
    '';
  };

  systemd.timers.ultra-media-download-stage = {
    wantedBy = lib.optionals stageCfg.enable ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = false;
      RandomizedDelaySec = "5m";
      AccuracySec = "1min";
      DeferReactivation = true;
      Unit = "ultra-media-download-stage.service";
    };
  };
}
