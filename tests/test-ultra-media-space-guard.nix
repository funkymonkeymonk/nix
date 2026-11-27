{pkgs, ...}: {
  drlightUltraMediaSpaceGuard =
    pkgs.runCommand "drlight-ultra-media-space-guard" {
      nativeBuildInputs = [pkgs.python3];
      scripts = ../modules/nixos/scripts;
      tests = ./test-ultra-media-space-guard.py;
    } ''
      PYTHONPATH="$scripts" python "$tests"
      touch $out
    '';
}
