{pkgs, ...}: {
  motdImageFetch =
    pkgs.runCommand "test-motd-image-fetch" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.gnugrep];
    } ''
      export MOTD_SCRIPT=${../modules/common/motd.sh}
      ${pkgs.bash}/bin/bash ${./test-motd.sh}
      touch $out
    '';
}
