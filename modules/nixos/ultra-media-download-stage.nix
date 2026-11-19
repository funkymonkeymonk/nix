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
  cleanupQueueArgument = lib.optionalString cleanupEnabled "--cleanup-queue-root ${lib.escapeShellArg cleanupQueueRoot} ";
  sshPort = 22;
  stageCfg = config.myConfig.ultraMediaDownloadStage;
  stageServices = ["ultra-media-download-stage"];
  cleanupServices = ["ultra-media-cleanup"];
  cleanupEnabled = stageCfg.cleanup.enable or false;
  remoteDiskConfig = stageCfg.remoteDisk;
  remoteDiskEnabled = remoteDiskConfig.enable;
  remoteDiskMetricsDirectory = "/run/ultra-media-metrics";
  arrSyncServices = [
    "radarr-media-config-sync"
    "sonarr-media-config-sync"
    "lidarr-media-config-sync"
  ];
  mkSecret = reference: path: {
    inherit reference path;
    mode = "0400";
    owner = "ultra-sync";
    group = "users";
    services = stageServices ++ lib.optionals cleanupEnabled cleanupServices;
  };
  mkSharedSecret = reference: path: {
    inherit reference path;
    mode = "0440";
    owner = "root";
    group = "media-management-secrets";
    services = stageServices ++ lib.optionals cleanupEnabled cleanupServices ++ arrSyncServices;
  };
in {
  imports = [
    ./ultra-media-cleanup.nix
    ({lib, ...}: {
      options.myConfig.ultraMediaDownloadStage = {
        enable = lib.mkEnableOption "completed Ultra download staging timer";
        cleanup = {
          enable = lib.mkEnableOption "automatic Ultra seedbox cleanup after verified local imports";
          privateTrackerRatioProtection.enable = lib.mkEnableOption "future private-tracker account-ratio cleanup gate (unknown trackers fail closed)";
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
      message = "Ultra remote disk monitoring requires the cleanup timer to be enabled";
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
    description = "Stage completed Transmission payloads for local Arr imports";
    after = ["network-online.target" "zfs-mount.service" "media-management-roots.service" "opnix-secrets.service"];
    wants = ["network-online.target"];
    requires = ["zfs-mount.service" "media-management-roots.service" "opnix-secrets.service"];
    unitConfig = {
      ConditionPathIsMountPoint = "/srv/media";
      RequiresMountsFor = ["/srv/media"];
    };
    serviceConfig = {
      Type = "exec";
      User = "ultra-sync";
      Group = "users";
      SupplementaryGroups = ["media-management-secrets"];
      UMask = "0002";
      ProtectSystem = "strict";
      RuntimeDirectory = "ultra-media";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "yes";
      StateDirectory = "ultra-media";
      StateDirectoryMode = "0700";
      ReadWritePaths = [stagingRoot "/run/ultra-media"];
    };
    environment.TMPDIR = "/run/ultra-media";
    script = ''
      set -euo pipefail
      export PYTHONPATH=${./scripts}
      exec ${pkgs.python3}/bin/python ${./scripts/ultra-media-download-stage.py} \
        --stage-downloads \
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
        ${cleanupQueueArgument}--rsync ${pkgs.rsync}/bin/rsync
    '';
  };

  systemd.timers.ultra-media-download-stage = {
    wantedBy = lib.optionals stageCfg.enable ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = false;
      RandomizedDelaySec = "5m";
      Unit = "ultra-media-download-stage.service";
    };
  };
}
