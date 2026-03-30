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
  config = lib.mkIf (lib.elem "developer" (cfg.roles or []) || lib.elem "workstation" (cfg.roles or [])) {
    home.packages = [watchCiJobsScript];
  };
}
