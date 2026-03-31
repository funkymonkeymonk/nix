{
  pkgs,
  lib,
  osConfig,
  ...
}: let
  cfg = osConfig.myConfig or {};

  # Read the watch-ci-jobs script
  watchCiJobsScript = pkgs.writeShellScriptBin "watch-ci-jobs" (
    builtins.readFile ./skills/internal/watch-ci-jobs/watch-ci-jobs.sh
  );
in {
  # Install watch-ci-jobs for developer and workstation roles
  config = lib.mkIf ((cfg.roles.developer.enable or false) || (cfg.roles.workstation.enable or false)) {
    home.packages = [watchCiJobsScript];
  };
}
