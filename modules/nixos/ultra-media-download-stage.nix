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
  sshPort = 22;
  stageCfg = config.myConfig.ultraMediaDownloadStage;
  stageServices = ["ultra-media-download-stage"];
  mkSecret = reference: path: {
    inherit reference path;
    mode = "0400";
    owner = "ultra-sync";
    group = "users";
    services = stageServices;
  };
in {
  imports = [
    ./ultra-media-cleanup.nix
    ({lib, ...}: {
      options.myConfig.ultraMediaDownloadStage.enable = lib.mkEnableOption "completed Ultra download staging timer";
    })
  ];

  users.users.ultra-sync = {
    isSystemUser = true;
    group = "users";
    description = "Stage completed Ultra downloads for local Arr imports";
  };

  myConfig.onepassword.secrets = {
    ultraMediaStageHost = mkSecret "Ultra Media Sync Config/host" hostPath;
    ultraMediaStageUsername = mkSecret "Ultra Media Sync Config/username" usernamePath;
    ultraMediaStageKnownHosts = mkSecret "Ultra Media Sync Config/knownHosts" knownHostsPath;
    ultraMediaStageKey = mkSecret "Ultra Media Sync Key/private key" keyPath;
    ultraMediaStageRpcUrl = mkSecret "Ultra Media Sync Config/rpcUrl" rpcUrlPath;
    ultraMediaStageDownloadRoot = mkSecret "Ultra Media Sync Config/completedDownloadsRoot" downloadRootPath;
    ultraMediaStageRpcUsername = mkSecret "Ultra - Transmission/username" rpcUsernamePath;
    ultraMediaStageRpcPassword = mkSecret "Ultra - Transmission/password" rpcPasswordPath;
  };

  systemd.services.ultra-media-download-stage = {
    description = "Stage completed Transmission payloads for local Arr imports";
    after = ["network-online.target" "zfs-mount.service" "media-management-roots.service" "opnix-secrets.service"];
    wants = ["network-online.target"];
    requires = ["zfs-mount.service" "media-management-roots.service" "opnix-secrets.service"];
    unitConfig = {
      ConditionPathIsMountPoint = "/srv/media";
      RequiresMountsFor = ["/srv/media"];
      OnSuccess = "ultra-media-cleanup.service";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "ultra-sync";
      Group = "users";
      UMask = "0002";
      ProtectSystem = "strict";
      ReadWritePaths = [stagingRoot];
    };
    script = ''
      set -euo pipefail
      export PYTHONPATH=${./scripts}
      exec ${pkgs.python3}/bin/python ${./scripts/ultra-media-download-stage.py} \\
        --stage-downloads \\
        --rpc-url ${lib.escapeShellArg rpcUrlPath} \\
        --download-root ${lib.escapeShellArg downloadRootPath} \\
        --ssh-host ${lib.escapeShellArg hostPath} \\
        --ssh-username ${lib.escapeShellArg usernamePath} \\
        --ssh-port ${toString sshPort} \\
        --known-hosts ${lib.escapeShellArg knownHostsPath} \\
        --ssh-key ${lib.escapeShellArg keyPath} \\
        --rpc-username ${lib.escapeShellArg rpcUsernamePath} \\
        --rpc-password ${lib.escapeShellArg rpcPasswordPath} \\
        --ssh ${pkgs.openssh}/bin/ssh \\
        --ssh-keygen ${pkgs.openssh}/bin/ssh-keygen \\
        --rsync ${pkgs.rsync}/bin/rsync
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
