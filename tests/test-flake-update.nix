{pkgs, ...}: {
  flakeUpdateRefreshesFixedOutputHashesTest =
    pkgs.runCommand "test-flake-update-refreshes-fixed-output-hashes"
    {
      bash = pkgs.bash;
      devenv = ../devenv.nix;
      refreshScript = ../scripts/refresh-fixed-output-hashes.sh;
      nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.jq];
    }
    ''
      set -euo pipefail

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

      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      mkdir -p "$tmp/mockbin"
      cat > "$tmp/manifest.json" <<'JSON'
      {
        "targets": [
          {
            "name": "fixture-npm-deps",
            "buildTarget": "fixture",
            "file": "overlay.nix",
            "start": "fixture =",
            "field": "hash",
            "bootstrap": "lib.fakeHash"
          }
        ]
      }
      JSON
      cat > "$tmp/overlay.nix" <<'NIX'
      fixture = (oldAttrs: {
        hash = "sha256-old";
      });
      NIX
      cat > "$tmp/mockbin/nix" <<'MOCK'
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      count=0
      if [ -f "$NIX_CALLS" ]; then
        count=$(wc -l < "$NIX_CALLS")
      fi
      printf '%s\n' "$*" >> "$NIX_CALLS"

      if [ "$count" -eq 0 ]; then
        if ! grep -q 'hash = lib.fakeHash;' "$TARGET_FILE"; then
          echo "FAIL: fixed-output hash was not bootstrapped before building"
          exit 1
        fi
        echo 'To correct the hash mismatch for fixture-npm-deps, use "sha256-updated="'
        exit 1
      fi

      grep -q 'hash = "sha256-updated=";' "$TARGET_FILE" || {
        echo "FAIL: hash mismatch result was not written before retrying"
        exit 1
      }
      MOCK
      cat > "$tmp/mockbin/git" <<'MOCK'
      #!${pkgs.bash}/bin/bash
      exit 1
      MOCK
      chmod +x "$tmp/mockbin/nix" "$tmp/mockbin/git"

      (
        cd "$tmp"
        PATH="$tmp/mockbin:$PATH" \
          NIX_CALLS="$tmp/nix-calls" \
          TARGET_FILE="$tmp/overlay.nix" \
          bash "$refreshScript" "$tmp/manifest.json"
      )

      if [ "$(wc -l < "$tmp/nix-calls")" -ne 2 ]; then
        echo "FAIL: the mismatched hash should be discovered then rebuilt with the replacement"
        exit 1
      fi

      grep -q 'hash = "sha256-updated=";' "$tmp/overlay.nix"
      echo "flake:update refreshes fixed-output hashes after updating inputs: OK"
      touch "$out"
    '';
}
