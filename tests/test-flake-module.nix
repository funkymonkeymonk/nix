# Unit tests for library/flake-module.nix
#
# library/flake-module.nix is a flake-parts module that (a) re-exports
# modules/ as flake.nixosModules.library, and (b) provides libraryLib
# (mk-system.nix's mkNixosSystem/mkDarwinSystem) and mkUser (mk-user.nix)
# as shared _module.args so any sibling flake-parts module imported
# alongside it (starting with the upcoming library/machines/zero.nix)
# can consume them without re-deriving libraryLib from scratch.
#
# This file is intentionally NOT yet imported by flake.nix — these tests
# exercise it standalone by calling it directly as a function, mirroring
# how flake-parts' module system would invoke it (passing `inputs` as a
# module argument) without requiring a full mkFlake wiring.
{pkgs, ...}: let
  lib = pkgs.lib;
  stubInputs = {
    nixpkgs = {inherit lib;};
  };
  result = import ../library/flake-module.nix {inputs = stubInputs;};
in {
  flakeModuleArgsTest =
    pkgs.runCommand "test-flake-module-args"
    {}
    ''
      echo "=== Testing library/flake-module.nix module args ==="

      ${
        if builtins.hasAttr "libraryLib" result._module.args
        then ''echo "  _module.args.libraryLib present: OK"''
        else ''echo "  FAIL: _module.args.libraryLib missing"; exit 1''
      }

      ${
        if builtins.isFunction result._module.args.libraryLib.mkNixosSystem
        then ''echo "  _module.args.libraryLib.mkNixosSystem is a function: OK"''
        else ''echo "  FAIL: _module.args.libraryLib.mkNixosSystem should be a function"; exit 1''
      }

      ${
        if builtins.isFunction result._module.args.libraryLib.mkDarwinSystem
        then ''echo "  _module.args.libraryLib.mkDarwinSystem is a function: OK"''
        else ''echo "  FAIL: _module.args.libraryLib.mkDarwinSystem should be a function"; exit 1''
      }

      ${
        if builtins.hasAttr "mkUser" result._module.args
        then ''echo "  _module.args.mkUser present: OK"''
        else ''echo "  FAIL: _module.args.mkUser missing"; exit 1''
      }

      ${
        if builtins.isFunction result._module.args.mkUser
        then ''echo "  _module.args.mkUser is a function: OK"''
        else ''echo "  FAIL: _module.args.mkUser should be a function"; exit 1''
      }

      ${
        let
          mkUserResult = result._module.args.mkUser "monkey" "me@willweaver.dev";
        in
          if (builtins.elemAt mkUserResult.users 0).name == "monkey"
          then ''echo "  _module.args.mkUser \"monkey\" \"me@willweaver.dev\" behaves like library/lib/mk-user.nix: OK"''
          else ''echo "  FAIL: _module.args.mkUser should behave like library/lib/mk-user.nix"; exit 1''
      }

      echo "All library/flake-module.nix module args tests passed"
      touch $out
    '';

  flakeModuleLibraryExportTest =
    pkgs.runCommand "test-flake-module-library-export"
    {}
    ''
      echo "=== Testing library/flake-module.nix flake.nixosModules.library export ==="

      ${
        if builtins.hasAttr "nixosModules" result.flake && builtins.hasAttr "library" result.flake.nixosModules
        then ''echo "  flake.nixosModules.library present: OK"''
        else ''echo "  FAIL: flake.nixosModules.library missing"; exit 1''
      }

      ${
        if builtins.isList result.flake.nixosModules.library.imports && builtins.length result.flake.nixosModules.library.imports == 1
        then ''echo "  flake.nixosModules.library.imports has exactly 1 entry (modules/): OK"''
        else ''echo "  FAIL: flake.nixosModules.library.imports should have exactly 1 entry"; exit 1''
      }

      echo "All library/flake-module.nix flake.nixosModules.library export tests passed"
      touch $out
    '';
}
