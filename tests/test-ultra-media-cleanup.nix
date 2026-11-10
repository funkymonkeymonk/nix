{pkgs, ...}: {
  drlightUltraMediaCleanup =
    pkgs.runCommand "drlight-ultra-media-cleanup" {
      nativeBuildInputs = [pkgs.python3];
      policy = ../modules/nixos/scripts/ultra-media-cleanup.py;
      adapter = ../modules/nixos/scripts/transmission_rpc.py;
      staging = ../modules/nixos/scripts/ultra-media-download-stage.py;
      tests = ./test-ultra-media-cleanup.py;
    } ''
      python "$tests" "$policy" "$adapter" "$staging"
      touch $out
    '';
}
