{pkgs, ...}: let
  stagingRoot = "/srv/media/.arr-staging";
in {
  # The stage unit's OnSuccess relationship is the only configured trigger.
  # This service has no timer, activation link, credentials, or network access.
  systemd.services.ultra-media-cleanup = {
    description = "Report-only Ultra media cleanup eligibility";
    after = ["ultra-media-download-stage.service"];
    unitConfig = {
      ConditionPathIsMountPoint = "/srv/media";
      RequiresMountsFor = ["/srv/media"];
    };
    path = [pkgs.python3];
    serviceConfig = {
      Type = "oneshot";
      User = "ultra-sync";
      Group = "users";
      UMask = "0002";
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      PrivateNetwork = true;
      ReadWritePaths = [stagingRoot];
    };
    script = ''
      set -euo pipefail
      exec ${pkgs.python3}/bin/python ${./scripts/ultra-media-cleanup.py} --report-only
    '';
  };
}
