{pkgs, ...}: {
  tailscaleOauthAuthKey =
    pkgs.runCommand "test-tailscale-oauth-authkey" {
      nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.jq];
    } ''
      export AUTHKEY_SCRIPT=${../scripts/tailscale-oauth-authkey.sh}
      export BASH_BIN=${pkgs.bash}/bin/bash
      export JQ_BIN=${pkgs.jq}/bin/jq
      ${pkgs.bash}/bin/bash ${./test-tailscale-oauth-authkey.sh}
      touch $out
    '';
}
