{pkgs, ...}: {
  flakeUpdateRefreshesFixedOutputHashesTest =
    pkgs.runCommand "test-flake-update-refreshes-fixed-output-hashes"
    {
      bash = pkgs.bash;
      devenv = ../devenv.nix;
      refreshScript = ../scripts/refresh-fixed-output-hashes.sh;
      syncScript = ../scripts/sync-devenv-inputs.sh;
      nativeBuildInputs = [pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.jq pkgs.python3];
    }
    ''
      set -euo pipefail

      task=$(sed -n '/"flake:update" = {/,/^[[:space:]]*};/p' "$devenv")
      update_line=$(grep -n 'nix flake update' <<< "$task" | cut -d: -f1)
      sync_line=$(grep -n 'sync-devenv-inputs.sh' <<< "$task" | cut -d: -f1)
      devenv_update_line=$(grep -n 'devenv update' <<< "$task" | cut -d: -f1)
      refresh_line=$(grep -n 'refresh-fixed-output-hashes.sh' <<< "$task" | cut -d: -f1)

      if [ -z "$update_line" ]; then
        echo "FAIL: flake:update must update flake inputs"
        exit 1
      fi

      if [ -z "$refresh_line" ]; then
        echo "FAIL: flake:update must refresh fixed-output dependency hashes"
        exit 1
      fi

      if [ -z "$sync_line" ] || [ -z "$devenv_update_line" ]; then
        echo "FAIL: flake:update must sync and update the devenv project lock"
        exit 1
      fi

      if [ "$update_line" -ge "$sync_line" ] \
        || [ "$sync_line" -ge "$devenv_update_line" ] \
        || [ "$devenv_update_line" -ge "$refresh_line" ]; then
        echo "FAIL: flake, devenv, and fixed-output hashes must update in order"
        exit 1
      fi

      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      cat > "$tmp/flake.lock" <<'JSON'
      {
        "nodes": {
          "root": {
            "inputs": {
              "nixpkgs": "nixpkgs",
              "bifrost": "bifrost",
              "devenv": "devenv"
            }
          },
          "nixpkgs": {
            "locked": {"rev": "new-nixpkgs"},
            "original": {"owner": "NixOS", "repo": "nixpkgs"}
          },
          "bifrost": {
            "locked": {"rev": "new-bifrost"},
            "original": {"owner": "maximhq", "repo": "bifrost"}
          },
          "devenv": {
            "locked": {"rev": "new-devenv"},
            "original": {"owner": "cachix", "repo": "devenv", "ref": "v2.4.0"}
          }
        }
      }
      JSON
      cat > "$tmp/devenv.yaml" <<'YAML'
      inputs:
        nixpkgs:
          url: github:NixOS/nixpkgs/old-nixpkgs
        bifrost:
          url: github:maximhq/bifrost/old-bifrost
          inputs:
            nixpkgs:
              follows: nixpkgs
        devenv:
          url: github:cachix/devenv/v2.4.0
        unrelated:
          url: github:example/unrelated/keep
      YAML

      bash "$syncScript" "$tmp/flake.lock" "$tmp/devenv.yaml"
      grep -q 'url: github:NixOS/nixpkgs/new-nixpkgs' "$tmp/devenv.yaml"
      grep -q 'url: github:maximhq/bifrost/new-bifrost' "$tmp/devenv.yaml"
      grep -q 'follows: nixpkgs' "$tmp/devenv.yaml"
      grep -q 'url: github:cachix/devenv/v2.4.0' "$tmp/devenv.yaml"
      grep -q 'url: github:example/unrelated/keep' "$tmp/devenv.yaml"

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
