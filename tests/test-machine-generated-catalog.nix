{pkgs, ...}: let
  source = builtins.path {
    path = ../.;
    name = "machine-generated-catalog-source";
  };
in {
  machineGeneratedCatalog =
    pkgs.runCommand "test-machine-generated-catalog" {
      nativeBuildInputs = [pkgs.coreutils pkgs.gnugrep pkgs.jq pkgs.nix];
      NIX_CONFIG = "experimental-features = nix-command";
      NIX_PATH = "nixpkgs=${pkgs.path}";
    } ''
      set -euo pipefail
      cp -r ${source} source
      export HOME="$PWD/home"
      mkdir -p "$HOME"
      export NIX_STATE_DIR="$HOME/nix-state"
      export MACHINE_CATALOG_LOADER="$PWD/source/library/machines/load-generated-catalog.nix"
      export MACHINE_CATALOG_CONSTRUCTOR="$PWD/source/library/machines/mk-catalog-machine.nix"
      export MACHINE_CATALOG="$PWD/source/library/machines/catalog.nix"
      export MACHINE_MACHINES_PROJECTION="$PWD/source/library/machines/devenv.nix"
      export MACHINE_FLAKE_PROJECTION="$PWD/source/library/machines/flake-configurations.nix"

      cat > evaluate.nix <<'NIX'
      let
        loadGenerated = import (builtins.getEnv "MACHINE_CATALOG_LOADER");
        mkCatalogMachine = import (builtins.getEnv "MACHINE_CATALOG_CONSTRUCTOR");
        mkUser = name: {inherit name;};
        nixosMachine = mkCatalogMachine {kind = "nixos";};
        darwinMachine = mkCatalogMachine {
          kind = "darwin";
          extraSpecialArgs = {inherit mkUser;};
        };
        existing =
          if builtins.getEnv "MACHINE_CATALOG_COLLISION" == "yes"
          then {zero = {};}
          else {};
        loaded = loadGenerated {
          directory = builtins.getEnv "MACHINE_CATALOG_DIR";
          inherit darwinMachine nixosMachine;
          existingCatalog = existing;
        };
      in
        builtins.mapAttrs (_: machine: {
          inherit (machine) builder kind system hostname;
        }) loaded
      NIX

      cat > integration.nix <<'NIX'
      let
        inputs.nixpkgs.lib = testLib;
        catalog = import (builtins.getEnv "MACHINE_CATALOG") {
          inherit inputs;
          generatedDirectory = builtins.getEnv "MACHINE_CATALOG_DIR";
        };
        machinesProjection = import (builtins.getEnv "MACHINE_MACHINES_PROJECTION") {
          inherit inputs catalog;
        };
        testLib = {
          filterAttrs = predicate: attrs:
            builtins.listToAttrs (builtins.filter (entry: predicate entry.name entry.value)
              (testLib.mapAttrsToList (name: value: {inherit name value;}) attrs));
          mapAttrs = builtins.mapAttrs;
          mapAttrsToList = function: attrs: map (name: function name (builtins.getAttr name attrs)) (builtins.attrNames attrs);
          optionalAttrs = condition: attrs: if condition then attrs else {};
        };
        flakeProjection = import (builtins.getEnv "MACHINE_FLAKE_PROJECTION") {
          inherit catalog;
          inputs.nixpkgs.lib = testLib;
          libraryLib = {
            mkNixosSystem = args: {inherit (args) system hostname;};
            mkDarwinSystem = args: {inherit (args) system hostname;};
          };
        };
        generatedCatalog = {
          generated-nixos = catalog.generated-nixos;
          generated-darwin = catalog.generated-darwin;
        };
      in {
        catalog = builtins.mapAttrs (_: machine: {
          inherit (machine) kind system hostname;
        }) generatedCatalog;
        machines = {
          generated-nixos = {
            system = machinesProjection.machines.generated-nixos.system;
            hasNixosProjection = builtins.hasAttr "nixos" machinesProjection.machines.generated-nixos;
          };
          generated-darwin = {
            system = machinesProjection.machines.generated-darwin.system;
            hasDarwinProjection = builtins.hasAttr "nix-darwin" machinesProjection.machines.generated-darwin;
          };
        };
        flake = {
          nixosNames = builtins.attrNames flakeProjection.flake.nixosConfigurations;
          darwinNames = builtins.attrNames flakeProjection.flake.darwinConfigurations;
          nixos = flakeProjection.flake.nixosConfigurations.generated-nixos;
          darwin = flakeProjection.flake.darwinConfigurations.generated-darwin;
        };
      }
      NIX

      evaluate() {
        MACHINE_CATALOG_DIR="$1" \
          MACHINE_CATALOG_COLLISION="''${2:-no}" \
          nix eval --impure --json --eval-store "$HOME/eval-store" --file evaluate.nix
      }

      mkdir -p fixtures/empty fixtures/valid
      printf '%s\n' 'not valid Nix and deliberately ignored' > fixtures/valid/ignored.txt
      cat > fixtures/valid/generated-nixos.nix <<'NIX'
      { darwinMachine, nixosMachine }:
      {
        generated-nixos = nixosMachine {
          secretProfile = "Personal";
          system = "aarch64-linux";
          hostname = "generated-nixos";
          modules = [];
        };
      }
      NIX

      empty_result=$(evaluate "$PWD/fixtures/empty")
      test "$empty_result" = '{}'
      absent_result=$(evaluate "$PWD/fixtures/absent")
      test "$absent_result" = '{}'
      generated_result=$(evaluate "$PWD/fixtures/valid")
      test "$generated_result" = '{"generated-nixos":{"builder":"mk-system","hostname":"generated-nixos","kind":"nixos","system":"aarch64-linux"}}'
      echo "empty and absent generated directories: OK"
      echo "valid generated entry and NixOS record projection: OK"
      echo "non-.nix files ignored: OK"

      mkdir -p fixtures/integrated
      cat > fixtures/integrated/generated-nixos.nix <<'NIX'
      { darwinMachine, nixosMachine }:
      {
        generated-nixos = nixosMachine {
          secretProfile = "Personal";
          system = "aarch64-linux";
          hostname = "generated-nixos-host";
          modules = [];
        };
      }
      NIX
      cat > fixtures/integrated/generated-darwin.nix <<'NIX'
      { darwinMachine, nixosMachine }:
      {
        generated-darwin = darwinMachine {
          secretProfile = "Personal";
          system = "aarch64-darwin";
          hostname = "generated-darwin-host";
          modules = [];
        };
      }
      NIX
      integration_result=$(MACHINE_CATALOG_DIR="$PWD/fixtures/integrated" \
        nix eval --impure --json --eval-store "$HOME/eval-store" --file integration.nix)
      jq -e '
        .catalog["generated-nixos"] == {"kind":"nixos","system":"aarch64-linux","hostname":"generated-nixos-host"} and
        .catalog["generated-darwin"] == {"kind":"darwin","system":"aarch64-darwin","hostname":"generated-darwin-host"} and
        .machines["generated-nixos"] == {"system":"aarch64-linux","hasNixosProjection":true} and
        .machines["generated-darwin"] == {"system":"aarch64-darwin","hasDarwinProjection":true} and
        (.flake.nixosNames | index("generated-nixos") != null) and
        (.flake.darwinNames | index("generated-darwin") != null) and
        .flake.nixos == {"system":"aarch64-linux","hostname":"generated-nixos-host"} and
        .flake.darwin == {"system":"aarch64-darwin","hostname":"generated-darwin-host"}
      ' <<< "$integration_result" >/dev/null || {
        printf '%s\n' "$integration_result" >&2
        exit 1
      }
      echo "actual catalog, Machines, and flake configuration projections include generated NixOS and Darwin entries: OK"

      mkdir -p fixtures/collision
      cat > fixtures/collision/zero.nix <<'NIX'
      { darwinMachine, nixosMachine }:
      {
        zero = nixosMachine {
          secretProfile = "Personal";
          system = "x86_64-linux";
          hostname = "zero-generated";
          modules = [];
        };
      }
      NIX
      if evaluate "$PWD/fixtures/collision" yes > collision.out 2> collision.err; then
        echo "collision with hand-maintained catalog name unexpectedly succeeded" >&2
        exit 1
      fi
      grep -F "zero" collision.err >/dev/null || {
        cat collision.err >&2
        exit 1
      }
      grep -F "collision" collision.err >/dev/null
      echo "catalog collision reports duplicate machine name: OK"

      mkdir -p fixtures/invalid-syntax
      printf '%s\n' 'this is not valid Nix !!!' > fixtures/invalid-syntax/broken.nix
      if evaluate "$PWD/fixtures/invalid-syntax" > invalid-syntax.out 2> invalid-syntax.err; then
        echo "invalid generated Nix file unexpectedly succeeded" >&2
        exit 1
      fi
      grep -F "broken.nix" invalid-syntax.err >/dev/null || {
        cat invalid-syntax.err >&2
        exit 1
      }
      echo "invalid generated file fails with filename context: OK"

      mkdir -p fixtures/invalid-shape
      cat > fixtures/invalid-shape/unsupported.nix <<'NIX'
      { darwinMachine, nixosMachine }:
      {
        first = {};
        second = {};
      }
      NIX
      if evaluate "$PWD/fixtures/invalid-shape" > invalid-shape.out 2> invalid-shape.err; then
        echo "unsupported generated entry shape unexpectedly succeeded" >&2
        exit 1
      fi
      grep -F "unsupported.nix" invalid-shape.err >/dev/null
      grep -F "exactly one machine" invalid-shape.err >/dev/null
      echo "unsupported generated entry shape fails clearly: OK"

      mkdir -p fixtures/filename-mismatch
      cat > fixtures/filename-mismatch/wrong-name.nix <<'NIX'
      { darwinMachine, nixosMachine }:
      {
        different-name = nixosMachine {
          secretProfile = "Personal";
          system = "x86_64-linux";
          hostname = "different-name";
          modules = [];
        };
      }
      NIX
      if evaluate "$PWD/fixtures/filename-mismatch" > filename-mismatch.out 2> filename-mismatch.err; then
        echo "filename and record mismatch unexpectedly succeeded" >&2
        exit 1
      fi
      grep -F "wrong-name.nix" filename-mismatch.err >/dev/null
      grep -F "does not match" filename-mismatch.err >/dev/null
      echo "generated filename/record mismatch fails clearly: OK"

      touch $out
    '';
}
