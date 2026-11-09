{pkgs, ...}: {
  flakeUpdateRefreshesFixedOutputHashesTest =
    pkgs.runCommand "test-flake-update-refreshes-fixed-output-hashes"
    {
      devenv = ../devenv.nix;
    }
    ''
      task=$(sed -n '/"flake:update" = {/,/^[[:space:]]*};/p' "$devenv")

      update_line=$(grep -n 'nix flake update' <<< "$task" | cut -d: -f1)
      refresh_line=$(grep -n 'refresh-fixed-output-hashes.sh' <<< "$task" | cut -d: -f1)

      if [ -z "$update_line" ]; then
        echo "FAIL: flake:update must update flake inputs"
        exit 1
      fi

      if [ -z "$refresh_line" ]; then
        echo "FAIL: flake:update must refresh fixed-output dependency hashes"
        exit 1
      fi

      if [ "$update_line" -ge "$refresh_line" ]; then
        echo "FAIL: fixed-output hashes must refresh after flake inputs update"
        exit 1
      fi

      touch "$out"
    '';
}
