{pkgs, ...}: let
  testPython = pkgs.python3.withPackages (pythonPackages: [pythonPackages.pyyaml]);
in {
  mediaAppApiReconciliation =
    pkgs.runCommand "media-app-api-reconciliation" {
      nativeBuildInputs = [testPython];
      tests = ./test_media_app_reconciliation.py;
      scripts = ../modules/nixos/scripts;
    } ''
      python "$scripts/servarr_reconcile.py" --help >/dev/null
      python "$scripts/bazarr_reconcile.py" --help >/dev/null
      python "$scripts/extract_media_api_key.py" --help >/dev/null
      python "$scripts/mylar3_config.py" --help >/dev/null
      python "$scripts/jellyfin_admin_auth.py" --help >/dev/null
      python "$tests" "$scripts"
      touch $out
    '';
}
